#!/bin/bash -l

# Print the start time
echo "Started at $(date)"

# Load the necessary modules
module load genrich/0.6

# Add a progress line to the log file
echo $'\n'"Checking inputs"

# Parse the arguments
while getopts i:o:e:a: flag
do
    case "$flag" in
        # -i flag specifies the input file
        i) input_file="$OPTARG";;
        # -o flag specifies the output directory
        o) out_dir="$OPTARG";;
        # -e flag specifies the directory with regions to exclude
        e) excluded_dir="$OPTARG";;
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

# Change the species ID to the common name instead of the genus-species name
if [ "$species" == "Homo sapiens" ]
then
    species="human"
elif [ "$species" == "Mus musculus" ]
then
    species="mouse"
else
    echo $'\n'"Unrecognized species :("
    exit 1
fi

# Get a comma separated list of files of regions to exclude
excluded="$(ls -1 "$excluded_dir/$species"*.bed | tr "\n" "," | sed 's|,$||g')"
if [ "$excluded" == "" ]
then
    echo "No excluded region files provided"
else
    echo "Excluded region file(s): $excluded"
    excluded="-E $excluded"
fi

# Create a directory to store temporary files for this ChIP experiment
chip_dir="$out_dir/tmp/$experiment"
mkdir -p "$chip_dir"

# Call peaks with Genrich
echo $'\n'"Calling peaks with Genrich"
if [ "$atac_mode" == "TRUE" ]
then
    # Call peaks using the ATAC-seq mode
    Genrich -t "$chip_bams" -c "$control_bams" \
    -o "$chip_dir/${factor}_${experiment}.narrowPeak" \
    -f "$chip_dir/${factor}_${experiment}.log" \
    -v -z -r -y -p 0.01 -a 100 -j "$excluded"
else
    # Call peaks using the default mode
    Genrich -t "$chip_bams" -c "$control_bams" \
    -o "$chip_dir/${factor}_${experiment}.narrowPeak" \
    -f "$chip_dir/${factor}_${experiment}.log" \
    -v -z -r -y -p 0.01 -a 100 "$excluded"
fi

# Move the output files to their final locations
echo $'\n'"Cleaning up"
gunzip "$chip_dir/${factor}_${experiment}.narrowPeak.gz"
mv "$chip_dir/${factor}_${experiment}.narrowPeak" "$out_dir/peaks/"
mv "$chip_dir/${factor}_${experiment}.log.gz" "$out_dir/peak_logs/"

# Delete the temporary directory for this experiment
rmdir "$chip_dir"

# Print a completion message and the end time
echo $'\n'"All done! Finished at $(date)"
