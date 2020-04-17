#!/bin/bash

# load modules needed for analysis (need -V flag in .conf to pass to qsub)
module load sratoolkit/2.9.2
module load fastqc/0.11.7
module load fastx-toolkit/0.0.14
module load samtools/1.10
module load bowtie2/2.3.4.1
module load python2/2.7.16
module load macs2/2.1.2.1
module load bedtools/2.27.1
module load zlib/1.2.11
module load openmpi/3.1.1
module load meme/5.0.3

# load cromwell and submit the wdl parallel workflow
module load cromwell/41
java -Dconfig.file=COFpendium_qsub.conf -jar $SCC_CROMWELL_BIN/cromwell.jar run COFpendium_run.wdl | tee cromwell_terminal_log.txt
