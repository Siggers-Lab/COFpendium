# COFpendium
~A compendium of COF-TF interactions inferred from genome-wide motif analysis of publicly available COF ChIP-seq data.~

It's really just a pipeline for analyzing ChIP-seq and/or ATAC-seq data these days. All of the COF-TF interaction inference stuff has been moved elsewhere. Specifically, it will download datasets from the SRA (or you can provide your own FASTQ files), remove low quality base calls from the ends of reads using Trimmomatic, run FASTQC to check the overall quality of both the raw reads and the trimmed reads, align reads to the genome using Bowtie2, and then identify peaks using Genrich.

NOTE: This will currently (and probably also futurely) only work on the BU SCC on the "siggers" project. If you don't have access, good luck out there.

## Installation
To make a copy of this repository, run the following in a terminal window:

```
git clone https://github.com/Siggers-Lab/COFpendium.git
```

This will create a new directory named "COFpendium" that contains all the contents of this repository.

If you already have a copy of the repository but it's out of date, navigate to the COFpendium directory and run the following to update your local copy:

```
git pull origin master
```

## Usage
### Creating a metadata file
The COFpendium pipeline requires a tab separated file containing metadata about the experiments you want to process. Siggers lab peeps, there is a Google Drive folder with instructions on making this metadata file; let me know if you can't find it or access it. Other peeps, this isn't going to work for you anyway, so don't waste your time.

### Running the analysis
The table below gives a brief description of the available options. Additional details for some options are below the table.

| Flag | Description                                                    | Default                      |
|------|----------------------------------------------------------------|------------------------------|
| i    | The path to the input COFpendium metadata file                 | -                            |
| o    | The path to the output directory                               | -                            |
| e    | The path to a directory with BED files of regions to exclude   | COFpendium/excluded_regions  |
| t    | The number of threads to use for preprocessing and aligning    | 1                            |
| m    | The maximum number of preprocessing jobs to run at once        | 20                           |
| a    | Should ATAC-seq mode be used?                                  | FALSE                        |

#### -e
The excluded regions directory contains a file (or files) of species-specific regions that should be excluded during the peak calling step. The file name must be of the format "\<species name\>*.bed", where "\<species name\>" is the common name of the species in question (i.e., "human" rather than "Homo sapiens", and "mouse" rather than "Mus musculus"). There are three files included:

* "human_excluded_regions.bed": This is a list of regions of the human genome that frequently produce artifacts in ChIP-seq data. I downloaded it from [the ENCODE project](https://www.encodeproject.org/files/ENCFF356LFX/@@download/ENCFF356LFX.bed.gz). There is no mouse equivalent of this file included because turns out none of the data I had came from mice, so I never bothered finding one. You're on your own if you want to do mouse stuff, sorry.
* "human_scaffolds_chrM.bed": This is a list of human genome scaffolds and the mitochondrial chromosome.
* "mouse_scaffolds_chrM.bed": This is a list of mouse genome scaffolds and the mitochondrial chromosome.

#### -t
I recommend using 16 threads for most datasets. For especially deep sequencing data (>100 million reads), you may want to use 32.

#### -m
Each preprocessing job creates several very large temporary files. If you have space limitations, set this to a lower number. If you kept using up all your disk space so your advisor bought a bunch more space, setting this to a higher number will allow more jobs to run at the same time and can reduce total wall clock runtime (i.e., the amount of real life time that passes before you get your results).

#### -a
Including this flag will tell the peak caller (Genrich) to use its ATAC-seq mode. I don't remember what the difference(s) is/are between its default mode and its ATAC-seq mode, but you can probably find it with some Googling, idk.

### Examples
Run the COFpendium pipeline on ChIP-seq data using 16 threads for each job:

```
bash /path/to/COFpendium/COFpendium.sh -i /path/to/chip_metadata.tsv -o /path/to/output_dir -t 16
```

Run the COFpendium pipeline on ATAC-seq data using 32 threads for each job and only allowing 5 jobs to run at once:

```
bash /path/to/COFpendium/COFpendium.sh -i /path/to/atac_metadata.tsv -o /path/to/output_dir -t 32 -m 5
```

