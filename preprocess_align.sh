#!/bin/bash -l

# Print the start time
echo "Started at $(date)"

# Load the necessary modules
module load sratoolkit/2.11.1
module load trimmomatic/0.36
module load fastqc/0.11.7
module load bowtie2/2.4.2
module load samtools/1.10

# Add a progress line to the log file
echo $'\n'"Checking inputs"

# Parse the arguments
while getopts i:o: flag
do
    case "$flag" in
        # -i flag specifies the input file
        i) input_file="$OPTARG";;
        # -o flag specifies the output directory
        o) out_dir="$OPTARG";;
    esac
done

# Get the inputs from the line corresponding to this task ID
IFS=$'\t' read sra experiment factor species bowtie_index fastq < \
<(head -n "$SGE_TASK_ID" "$input_file" | tail -n 1)

# Add some lines to the log file listing the inputs
echo "Factor: $factor"
echo "Experiment: $experiment"
echo "SRA number: $sra"
echo "Species: $species"
echo "Bowtie 2 index: $bowtie_index"
echo "FASTQ file(s): $fastq"

# Check if the reads for this SRA number are single- or paired-end
echo $'\n'"Checking if reads are single-end or paired-end"
if [ "$fastq" != "NA" ]
then
    # Check how many comma-separated FASTQ files were provided
    IFS="," read -ra fastq_array <<< "$fastq"
    if [ "${#fastq_array[@]}" == 1 ] && [ -f "${fastq_array[0]}" ]
    then
        echo "Reads detected as single-end"
        single_paired="single"
    elif [ "${#fastq_array[@]}" == 1 ] && [ ! -f "${fastq_array[0]}" ]
    then
        echo "Uh oh, the following FASTQ file doesn't exist:"
        echo "${fastq_array[0]}"
        echo "Please double check the path and try again. :("
        exit 1
    elif [ "${#fastq_array[@]}" == 2 ] \
    && [ -f "${fastq_array[0]}" ] && [ -f "${fastq_array[1]}" ]
    then
        echo "Reads detected as paired-end"
        single_paired="paired"
    elif [ "${#fastq_array[@]}" == 2 ] \
    && [[ ! -f "${fastq_array[0]}" || ! -f "${fastq_array[1]}" ]]
    then
        echo "Uh oh, at least one of the following FASTQ files doesn't exist:"
        echo "${fastq_array[0]}"
        echo "${fastq_array[1]}"
        echo "Please double check the paths and try again. :("
        exit 1
    else
        echo -n "Uh oh, couldn't determine if reads are "
        echo "single-end or paired-end. :("
        echo -n "Please make sure the fastq and control_fastq columns "
        echo "of the input metadata file contain one of the following:"
        echo "Exactly one FASTQ file path"
        echo "Exactly two FASTQ file paths separated by a comma with no spaces"
        echo "NA"
        exit 1
    fi
else
    # Donwload the first read and see how many lines it is
    single_paired=("$(fastq-dump -X 1 -Z --split-spot "$sra" | wc -l)")
    if [ "$single_paired" == 4 ]
    then
        echo "Reads detected as single-end"
        single_paired="single"
    elif [ "$single_paired" == 8 ]
    then
        echo "Reads detected as paired-end"
        single_paired="paired"
    else
        echo "Uh oh, looks like fastq-dump failed because it's garbage. :("
        exit 1
    fi
fi

# Create a directory name to store tmp files for this SRA number
sra_dir="$out_dir/tmp/$sra"
mkdir -p "$sra_dir"

if [ "$fastq" != "NA" ]
then
    # Copy the FASTQ file(s) into the tmp directory
    echo $'\n'"Copying FASTQ file(s)"
    if [ "${#fastq_array[@]}" == 1 ]
    then
        # Copy over the single-end FASTQ file with the appropriate extension
        if [[ "${fastq_array[0]}" =~ .*\.gz ]]
        then
            cp "${fastq_array[0]}" "$sra_dir/$sra.fastq.gz"
        else
            cp "${fastq_array[0]}" "$sra_dir/$sra.fastq"
        fi
    else
        # Copy over the mate 1 FASTQ file with the appropriate extension
        if [[ "${fastq_array[0]}" =~ .*\.gz ]]
        then
            cp "${fastq_array[0]}" "$sra_dir/${sra}_1.fastq.gz"
        else
            cp "${fastq_array[0]}" "$sra_dir/${sra}_1.fastq"
        fi
        # Copy over the mate 2 FASTQ file with the appropriate extension
        if [[ "${fastq_array[1]}" =~ .*\.gz ]]
        then
            cp "${fastq_array[1]}" "$sra_dir/${sra}_2.fastq.gz"
        else
            cp "${fastq_array[1]}" "$sra_dir/${sra}_2.fastq"
        fi
    fi
else
    # Download the SRA file
    echo -n $'\n'"Downloading SRA file"
    prefetch -o "$sra_dir/$sra.sra" "$sra"

    # Validate the download was successful
    echo $'\n'"Checking download was successful"

    # Make sure the .sra file was downloaded
    if [ -f "sra_dir/$sra.fastq" ]
    then
        echo "Uh oh, looks like prefetch failed because it's garbage. :("
        exit 1
    else
        echo "SRA file $sra_dir/$sra.sra exists"
    fi

    # Make sure the downloaded .sra file is correct
    vdb-validate "$sra_dir" 2> >(tee "$sra_dir/vdb_log.txt")
    # If everything worked, all the lines should contain "info:" (I think...)
    error_wc=("$(grep -v "info:" "$sra_dir/vdb_log.txt" | wc -l)")
    if [ -f "$sra_dir/vdb_log.txt" ] && [ "$error_wc" == 0 ]
    then
        echo "No errors detected"
    else
        echo "Uh oh, looks like something went wrong with the download. :("
        exit 1
    fi

    # Get the FASTQ file(s)
    echo $'\n'"Extracting FASTQ file(s)"
    fasterq-dump "$sra" -O "$sra_dir" -t "$sra_dir" -e "$NSLOTS" \
    --split-3 -L fatal

    # Make sure the FASTQ file(s) were extracted successfully
    if [[ ! -f "$sra_dir/$sra.fastq" ]] \
    && [[ ! -f "$sra_dir/${sra}_1.fastq" || ! -f "$sra_dir/${sra}_2.fastq" ]]
    then
        echo "Uh oh, looks like fasterq-dump failed because it's garbage. :("
        exit 1
    fi
fi

# Check if the FASTQ file(s) are already compressed and gzip them if not
if [ -f "$sra_dir/$sra.fastq" ] \
|| [ -f "$sra_dir/${sra}_1.fastq" ] || [ -f "$sra_dir/${sra}_2.fastq" ]
then
    echo $'\n'"Compressing FASTQ file(s)"
    gzip "$sra_dir/"*".fastq"
else
    echo $'\n'"FASTQ file(s) are already compressed"
fi

# Make sure the FASTQ file(s) were gzipped successfully
if [[ ! -f "$sra_dir/$sra.fastq.gz" ]] \
&& [[ ! -f "$sra_dir/${sra}_1.fastq.gz" || ! -f "$sra_dir/${sra}_2.fastq.gz" ]]
then
    echo "Uh oh, looks like gzip failed unexpectedly. :("
    exit 1
fi

# Remove low-quality bases and reads that are too short with Trimmomatic
echo $'\n'"Trimming reads with Trimmomatic"
if [ "$single_paired" == "single" ]
then
    # Change the name of the FASTQ file to include the factor and experiment
    mv "$sra_dir/$sra.fastq.gz" "$sra_dir/${factor}_${experiment}_$sra.fastq.gz"

    # Trim reads
    trimmomatic SE -threads "$NSLOTS" \
    "$sra_dir/${factor}_${experiment}_$sra.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_filtered.fastq.gz" \
    SLIDINGWINDOW:4:20 MINLEN:20 \
    || trimmomatic SE -phred33 -threads "$NSLOTS" \
    "$sra_dir/${factor}_${experiment}_$sra.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_filtered.fastq.gz" \
    SLIDINGWINDOW:4:20 MINLEN:20
else
    # Change the name of the FASTQ files to include the factor name
    mv "$sra_dir/${sra}_1.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_1.fastq.gz"
    mv "$sra_dir/${sra}_2.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_2.fastq.gz"

    # Trim reads
    trimmomatic PE -threads "$NSLOTS" \
    "$sra_dir/${factor}_${experiment}_${sra}_1.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_2.fastq.gz" \
    -baseout "$sra_dir/${factor}_${experiment}_${sra}_filtered.fastq.gz" \
    SLIDINGWINDOW:4:20 MINLEN:20 \
    || trimmomatic PE -phred33 -threads "$NSLOTS" \
    "$sra_dir/${factor}_${experiment}_${sra}_1.fastq.gz" \
    "$sra_dir/${factor}_${experiment}_${sra}_2.fastq.gz" \
    -baseout "$sra_dir/${factor}_${experiment}_${sra}_filtered.fastq.gz" \
    SLIDINGWINDOW:4:20 MINLEN:20

    # Remove the files of unpaired reads
    rm -f "$sra_dir/${factor}_${experiment}_${sra}_filtered_"*"U.fastq.gz"
fi

# Create a directory to store the FastQC output files for this SRA number
fastqc_dir="$out_dir/fastqc/${factor}_${experiment}_${sra}"
mkdir -p "$fastqc_dir"

# Check the quality of the raw reads and the trimmed reads with FastQC
echo $'\n'"Checking read quality with FastQC"
fastqc -q -t "$NSLOTS" -o "$fastqc_dir" \
"$sra_dir/${factor}_${experiment}_${sra}"*".fastq.gz"

# Align to the genome with Bowtie 2
echo $'\n'"Aligning to genome with Bowtie 2"
if [ "$single_paired" == "single" ]
then
    bowtie2 -x "$bowtie_index" \
    -U "$sra_dir/${factor}_${experiment}_${sra}_filtered.fastq.gz" \
    --very-sensitive-local -p "$NSLOTS" \
    | samtools sort -n -o "$sra_dir/${factor}_${experiment}_${sra}.bam"
else
    bowtie2 -x "$bowtie_index" \
    -1 "$sra_dir/${factor}_${experiment}_${sra}_filtered_1P.fastq.gz" \
    -2 "$sra_dir/${factor}_${experiment}_${sra}_filtered_2P.fastq.gz" \
    --very-sensitive-local -X 2000 -p "$NSLOTS" \
    | samtools sort -n -o "$sra_dir/${factor}_${experiment}_${sra}.bam"
fi

# Move the final BAM file to the output BAM directory
echo $'\n'"Cleaning up"
mv "$sra_dir/${factor}_${experiment}_${sra}.bam" "$out_dir/bam/"

# Delete all the temporary files for this SRA number
rm -rf "$sra_dir"

# Print a completion message and the end time
echo $'\n'"All done! Finished at $(date)"
