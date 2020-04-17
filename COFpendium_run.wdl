workflow COFpendium  {
	
	# read in the COFpendium metadata with the SRA accession numbers
	Array[Array[String]] sraSamples = read_tsv('COFpendium_metadata.tsv')
	
	# for each SRA accession perform a full ChIP seq reanalysis ending with a motif analysis
	scatter (sraSample in sraSamples) {
		call sraMotifAnalysis { input: sraName=sraSample[0] }
	}
	
	# concatenate the collections of motif analysis files across all datasets reanalyzed
	call motifFileConcat { input: motifFullFiles=sraMotifAnalysis.outFull, motifhTFFiles=sraMotifAnalysis.outhTF }

}

task sraMotifAnalysis {
	
	String sraName
	
    command <<<
	
		# fetch data set from ncbi
		fastq-dump ${sraName}
		gzip ${sraName}.fastq

		# read-level QC and filtering
		fastqc ${sraName}.fastq.gz
		zcat ${sraName}.fastq.gz | fastq_quality_filter -Q33 -q 30 -p 60 -o ${sraName}_filt.fastq
		gzip ${sraName}_filt.fastq
		fastqc ${sraName}_filt.fastq.gz

		# map to human genome and filter (optical duplicates, unmapped reads, and MAPQ score)
		bowtie2 -x /project/siggers/Bowtie2_Indexes/hg38/Homo_sapiens/UCSC/hg38/Sequence/Bowtie2Index/genome -U ${sraName}_filt.fastq.gz -S ${sraName}.sam --very-sensitive-local
		samtools view -bS ${sraName}.sam | samtools sort - > ${sraName}_sorted.bam
		rm -f ${sraName}.sam
		samtools index ${sraName}_sorted.bam
		samtools view -b -F 1548 -q 30 ${sraName}_sorted.bam | samtools rmdup -s - ${sraName}_sorted_filt.bam
		samtools index ${sraName}_sorted_filt.bam

		# call peaks
		macs2 callpeak -t ${sraName}_sorted_filt.bam -f BAM -n ${sraName} -g hs

		# add flanks (250bp) to peaks summits, filter weird chr, and fetch sequences for fasta-formatted file
		awk 'BEGIN {OFS="\t"}; {print $1,$2-250,$3+250,$4,$5}' ${sraName}_summits.bed | egrep -v 'chrUn|chrM|random' > ${sraName}_flanks.bed
		bedtools getfasta -name -fi /project/siggers/Bowtie2_Indexes/hg38/Homo_sapiens/UCSC/hg38/Sequence/WholeGenomeFasta/genome.fa -bed ${sraName}_flanks.bed | fold -w 60 > ${sraName}.fa

		# run motif centrality analysis using both the full JASPAR CORE and just the subset on hTF v01
		centrimo --oc ${sraName}_centrimo_full ${sraName}.fa /projectnb/siggers/data/hTF_array_project/COFpendium/pipeline_tests/qsub_WDL_tests/JASPAR2018_CORE_vertebrates_non-redundant.meme
		centrimo --oc ${sraName}_centrimo_hTF ${sraName}.fa /projectnb/siggers/data/hTF_array_project/COFpendium/pipeline_tests/qsub_WDL_tests/JASPAR2018_hTF_only.meme

		# tag each motif file with the dataset name and filter motif files to include only data lines
		awk 'BEGIN {OFS="\t"}; {$1="${sraName}"; print ;}' ${sraName}_centrimo_full/centrimo.tsv | egrep 'MA' > ${sraName}_full.tsv
		awk 'BEGIN {OFS="\t"}; {$1="${sraName}"; print ;}' ${sraName}_centrimo_hTF/centrimo.tsv | egrep 'MA' > ${sraName}_hTF.tsv
	
    >>>
    output {
        File outFull = "${sraName}_full.tsv"
        File outhTF = "${sraName}_hTF.tsv"
    }
	
}

task motifFileConcat {
	
	Array[File] motifFullFiles
	Array[File] motifhTFFiles
	
	command <<<
		cat ${sep=' ' motifFullFiles} > COFpendium_full.txt
		cat ${sep=' ' motifhTFFiles} > COFpendium_hTF.txt
	>>>
	output {
		File concatFull = "COFpendium_full.txt"
		File concathTF = "COFpendium_hTF.txt"
	}
	
}
