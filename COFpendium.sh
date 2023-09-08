#!/bin/bash -l

# Set the paths to the human genome files
hs_bowtie_index="/projectnb/siggers/genomes/hg38/bowtie2_index/genome"
hs_genome="/projectnb/siggers/genomes/hg38/sequences/genome.fa"

# Set the paths to the mouse genome files
mm_bowtie_index="/projectnb/siggers/genomes/mm10/bowtie2_index/genome"
mm_genome="/projectnb/siggers/genomes/mm10/sequences/genome.fa"

# Set the default values for optional parameters
script_dir="$(dirname $(realpath $0))"
excluded_dir="$script_dir/excluded_regions"
num_threads=1
max_concurrent_tasks=20
atac_mode="FALSE"

# Parse the arguments
while getopts i:o:e:t:m:a flag
do
    case "$flag" in
        # -i flag specifies the input COFpendium metadata file
        i) metadata="$OPTARG";;
        # -o flag specifies the output directory
        o) out_dir="$OPTARG";;
        # -e flag specifies the directory with regions to exclude
        e) excluded_dir="$OPTARG";;
        # -t flag specifies the number of threads to use for preprocessing
        t) num_threads="$OPTARG";;
        # -m flag specifies the max number of preprocessing jobs to run at once
        m) max_concurrent_tasks="$OPTARG";;
        # -a flag turns on ATAC-seq mode
        a) atac_mode="TRUE";;
    esac
done

# Make sure the path to the provided directories are the absolute paths
out_dir="$(realpath $out_dir)"
excluded_dir="$(realpath $excluded_dir)"

# Create the output directory structure if it doesn't already exist
mkdir -p "$out_dir"/{fastqc,bam,peaks,peak_logs,summary,logs,tmp}

# Delete anything that already exists in the tmp directory
rm -rf "$out_dir/tmp/"*

# Create a file listing all SRA numbers, experiment IDs, factors, and species
awk 'BEGIN{OFS = FS = "\t"} /^[^#]/ {print $1, $3, $4, $5, $6} \
/^[^#]/ && $2 != "NONE" {print $2, "control", "none", $5, $7}' \
"$metadata" | sort -u > "$out_dir/tmp/all_sras.tsv"

# Check for duplicate SRA numbers
readarray -t dups < <(cut -f1 "$out_dir/tmp/all_sras.tsv" | sort | uniq -d)

# Print an error message and stop execution if there are duplicate SRA numbers
if [ "${#dups[@]}" != 0 ]
then
    echo "Uh oh, looks like you have duplicate SRA numbers. :("
    echo -n "Please check your metadata file and remove duplicates"
    echo " of the following SRA number(s):"
    echo "${dups[@]}"
    exit
fi

# Create a file of SRA numbers that are missing BAM files
while IFS=$'\t' read -r sra experiment factor species fastq
do
    # If there isn't a BAM file for this SRA number, add a line
    if [ ! -f "$out_dir/bam/${factor}_${experiment}_${sra}.bam" ]
    then
        # Add the SRA number, experiment, factor, and species to the line
        echo -n "$sra"$'\t'"$experiment"$'\t'"$factor"$'\t'"$species" \
        >> "$out_dir/tmp/no_bams.tsv"
        # Add the path to the bowtie2 index to use
        if [ "$species" == "Homo sapiens" ]
        then
            echo -n $'\t'"$hs_bowtie_index" >> "$out_dir/tmp/no_bams.tsv"
        elif [ "$species" == "Mus musculus" ]
        then
            echo -n $'\t'"$mm_bowtie_index" >> "$out_dir/tmp/no_bams.tsv"
        else
            echo $'\n'"Unrecognized species: $species"
            echo "Currently accepted species: 'Homo sapiens', 'Mus musculus'"
            echo "Please make sure your species' names match EXACTLY"
            exit 1
        fi
        # Add the path to the FASTQ file(s)
        echo $'\t'"$fastq" >> "$out_dir/tmp/no_bams.tsv"
    fi
done < "$out_dir/tmp/all_sras.tsv"

# Create a file listing all experiment IDs, factors, species, and BAM files
grep -v "^#" "$metadata" | awk -v out_dir="$out_dir" 'BEGIN{OFS = FS = "\t"} \
{x = $3 "\t" $4 "\t" $5; \
a[x] = a[x]","out_dir"/bam/"$4"_"$3"_"$1".bam"; \
if($2 == "NONE") {b[x] = b[x]",null"} \
else {b[x] = b[x]","out_dir"/bam/none_control_"$2".bam"}} \
END{for(x in a) print x, a[x], b[x]}' \
| sed 's|\t,|\t|g' \
> "$out_dir/tmp/all_experiments.tsv"

# Create a file of experiments that are missing narrowPeak files
while IFS=$'\t' read -r experiment factor remainder
do
    # If there isn't a narrowPeak file for this experiment add a line
    if [ ! -f "$out_dir/peaks/${factor}_${experiment}.narrowPeak" ]
    then
        # Add the experiment, factor, and remaining fields to the line
        echo "$experiment"$'\t'"$factor"$'\t'"$remainder" \
        >> "$out_dir/tmp/no_peaks.tsv"
    fi
done < "$out_dir/tmp/all_experiments.tsv"

# Initialize variables to store the qsub job IDs
align_jid="NONE"
peaks_jid="NONE"

# If the no_bams.tsv file exists, submit an array job
if [ -f "$out_dir/tmp/no_bams.tsv" ]
then
    # Figure out how many jobs to submit based on how many lines are in the file
    num_lines=($(wc -l "$out_dir/tmp/no_bams.tsv"))

    # Submit an array job to download, process, and align the FASTQ files
    align_jid=$(qsub -terse -N preprocess_align -j y -wd "$out_dir/tmp" \
    -o "$out_dir/logs" -t 1-"$num_lines" -pe omp "$num_threads" \
    -tc "$max_concurrent_tasks" \
    "$script_dir/preprocess_align.sh" -i "$out_dir/tmp/no_bams.tsv" \
    -o "$out_dir")

    # Keep only the base job ID
    align_jid="${align_jid%.*}"

    # Print a qsub job submission message
    echo "Your job $align_jid "'("preprocess_align")'" has been submitted"
else
    echo "There are already BAM files for all experiments. Yay!"
fi

# If the no_peaks.tsv file exists, submit an array job
if [ -f "$out_dir/tmp/no_peaks.tsv" ]
then
    # Figure out how many jobs to submit based on how many lines are in the file
    num_lines=($(wc -l "$out_dir/tmp/no_peaks.tsv"))

    # Submit an array job to call peaks
    peaks_jid=$(qsub -terse -N call_peaks -hold_jid "$align_jid" -j y \
    -o "$out_dir/logs" -t 1-"$num_lines" \
    "$script_dir/call_peaks.sh" -i "$out_dir/tmp/no_peaks.tsv" \
    -o "$out_dir" -e "$excluded_dir" -a "$atac_mode")

    # Keep only the base job ID
    peaks_jid="${peaks_jid%.*}"

    # Print a qsub job submission message
    echo "Your job $peaks_jid "'("call_peaks")'" has been submitted"
else
    echo "There are already narrowPeak files for all experiments. Yay!"
fi

# Submit a job to remove empty log files and tmp files and to rename log files
qsub -N clean_up -hold_jid "$align_jid,$peaks_jid" -j y -o "$out_dir/logs" \
"$script_dir/clean_up.sh" -o "$out_dir" -a "$align_jid" -p "$peaks_jid"
