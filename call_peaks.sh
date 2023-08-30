#!/bin/bash -l

# Print the start time
echo "Started at $(date)"

# Load the necessary modules
module load genrich/0.6

# Add a progress line to the log file
echo $'\n'"Checking inputs"

# Parse the arguments
while getopts i:o:r:a: flag
do
    case "$flag" in
        # -i flag specifies the input file
        i) input_file="$OPTARG";;
        # -o flag specifies the output directory
        o) out_dir="$OPTARG";;
        # -r flag specifies the directory with reference files
        r) reference_dir="$OPTARG";;
        # -a flag specifies whether to use ATAC-seq mode
        a) atac_mode="$OPTARG";;
    esac
done

# Get the inputs from the line corresponding to this task ID
IFS=$'\t' read experiment factor species chip_bams control_bams < \
<(head -n "$SGE_TASK_ID" "$input_file" | tail -n 1)

# Add some lines to the log file listing the inputs
echo "Factor: $factor"
echo "Experiment: $experiment"
echo "Species: $species"
echo "Using the excluded regions file in: $reference_dir"
if [ "$atac_mode" == "TRUE" ]
then
    echo "Using ATAC-seq mode"
fi

# Make sure the ChIP BAM files exist, and halt execution if they don't
n=1
while IFS="," read -ra bams
do
    for bam in "${bams[@]}"
    do
        if [ ! -f "$bam" ]
        then
            echo "$bam does not exist. :("
            exit
        else
            echo "ChIP file $n: $bam"
        fi
        n="$((n+1))"
    done
done <<< "$chip_bams"

# Make sure the control BAM files exist or are null, and halt execution if not
n=1
while IFS="," read -ra bams
do
    for bam in "${bams[@]}"
    do
        if [ ! -f "$bam" ] && [ "$bam" != "null" ]
        then
            echo "$bam does not exist. :("
            exit
        else
            echo "Control file $n: $bam"
        fi
        n="$((n+1))"
    done
done <<< "$control_bams"

# Create a directory to store temporary files for this ChIP experiment
chip_dir="$out_dir/tmp/$experiment"
mkdir -p "$chip_dir"

# Change the species ID to the common name instead of the genus-species name
if [ "$species" == "Homo sapiens" ]
then
    species="human"
elif [ "$species" == "Mus musculus" ]
then
    species="mouse"
    echo $'\n'"I don't have excluded regions for mouse datsets yet... :("
    exit
else
    echo $'\n'"Unrecognized species :("
    exit 1
fi

# Call peaks with Genrich
echo $'\n'"Calling peaks with Genrich"
if [ "$atac_mode" == "TRUE" ]
then
    # Call peaks using the ATAC-seq mode
    Genrich -t "$chip_bams" -c "$control_bams" \
    -o - -E "$reference_dir/${species}_excluded_regions.bed" -r -y -j -e chrM \
    | grep -vE "(GL000|KI270|GL456|JH584)" \
    > "$chip_dir/${factor}_${experiment}.narrowPeak"
else
    # Call peaks using the default mode
    Genrich -t "$chip_bams" -c "$control_bams" \
    -o - -E "$reference_dir/${species}_excluded_regions.bed" -r -y -e chrM \
    | grep -vE "(GL000|KI270|GL456|JH584)" \
    > "$chip_dir/${factor}_${experiment}.narrowPeak"
fi

# Move the output file to out_dir/peaks
echo $'\n'"Cleaning up"
mv "$chip_dir/${factor}_${experiment}.narrowPeak" "$out_dir/peaks/"

# Delete the temporary directory for this experiment
rmdir "$chip_dir"

# Print a completion message and the end time
echo $'\n'"All done! Finished at $(date)"
