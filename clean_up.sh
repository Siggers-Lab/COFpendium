#!/bin/bash -l

# Load the necessary modules
module load bedtools/2.27.1

# Parse the arguments
while getopts o:a:p: flag
do
    case "$flag" in
        # -o flag specifies the output directory
        o) out_dir="$OPTARG";;
        # -a flag specifies the preprocess_align job ID
        a) align_jid="$OPTARG";;
        # -p flag specifies the call_peaks job ID
        p) peaks_jid="$OPTARG";;
    esac
done

# Rename the preprocess_align log files to include the experiment info
if [ "$align_jid" != "NONE" ]
then
    cat -n "$out_dir/tmp/no_bams.tsv" \
    | while IFS=$'\t' read index sra experiment factor dummy
    do
        # Remove the whitespace from the log file index number
        index=("${index// /}")

        # Rename the log file
        mv "$out_dir/logs/preprocess_align.o$align_jid.$index" \
        "$out_dir/logs/preprocess_align_${factor}_${experiment}_${sra}.txt"
    done
fi

# Rename the call_peaks log files to include the experiment info
if [ "$peaks_jid" != "NONE" ]
then
    cat -n "$out_dir/tmp/no_peaks.tsv" \
    | while IFS=$'\t' read index experiment factor dummy
    do
        # Remove the whitespace from the log file index number
        index=("${index// /}")

        # Rename the log file
        mv "$out_dir/logs/call_peaks.o$peaks_jid.$index" \
        "$out_dir/logs/call_peaks_${factor}_${experiment}.txt"
    done
fi

# Combine all the peaks from all the datasets into one file
rm -f "$out_dir/summary/all_peaks.narrowPeak"
for filename in "$out_dir/peaks/"*
do
    grep -H "" "$filename" \
    | sed 's|.*/peaks/||g' \
    | sed 's|\.narrowPeak:|\t|g' \
    | awk 'BEGIN{OFS = FS = "\t"} {$5 = $1 "_" $5}1' \
    | cut -f 2-11 >> "$out_dir/summary/all_peaks.narrowPeak"
done

# Remove empty log files
find "$out_dir/logs" -size 0 -exec rm '{}' \;

# Remove everything in the tmp directory
rm -rf "$out_dir/tmp"
