-------------------------------------------------------
-- parameter section
-------------------------------------------------------
%default KEYWORD_SUBDIR '/keyword'
%default TITLE_SUBDIR '/title'
%default ABSTRACT_SUBDIR '/abstract'
%default JOINED_SUBDIR '/weighted'
%default SIM_SUBDIR '/similarity'

%default KEYWORD_WEIGHT 1.0
%default TITLE_WEIGHT 1.0
%default ABSTRACT_WEIGHT 1.0
%default sample 0.1

%default inputPath hdfs://hadoop-master:8020/user/akawa/full/hbase-dump/mproto-m*
%default outputPath hdfs://hadoop-master:8020/user/akawa/full/similarity/tfidf3
%default commonJarsPath ../oozie/similarity/workflow/lib/*.jar
%default parallel 40

-------------------------------------------------------
-- register section
-------------------------------------------------------
REGISTER /usr/lib/zookeeper/zookeeper-3.4.3-cdh4.0.1.jar;
REGISTER /usr/lib/hbase/hbase-0.92.1-cdh4.0.1-security.jar
REGISTER /usr/lib/hbase/lib/guava-11.0.2.jar;

REGISTER '$commonJarsPath'

-------------------------------------------------------
-- define section
-------------------------------------------------------
DEFINE WeightedTFIDF pl.edu.icm.coansys.similarity.pig.udf.TFIDF('weighted');
DEFINE StemmedPairs pl.edu.icm.coansys.similarity.pig.udf.StemmedPairs();
DEFINE StopWordFilter pl.edu.icm.coansys.similarity.pig.udf.StopWordFilter();

-------------------------------------------------------
-- import section
-------------------------------------------------------
IMPORT 'macros.pig';

-------------------------------------------------------
-- business code section
-------------------------------------------------------
set default_parallel $parallel

doc = load_bwndata_metadata_hdfs('$inputPath', $sample);

-- stem, clean, filter out
doc_keyword = stem_and_filter_out(doc, 'keywords');
doc_title = stem_and_filter_out(doc, 'title');
doc_abstract = stem_and_filter_out(doc, 'abstract');

-- get distinct words
doc_term_K = FOREACH doc_keyword GENERATE docId, term;
doc_term_T = FOREACH doc_title GENERATE docId, term;
doc_term_A = FOREACH doc_abstract GENERATE docId, term;
doc_term_union = UNION doc_term_K, doc_term_A, doc_term_T;
doc_term_distinct = DISTINCT doc_term_union;

-- calculate tf-idf for each group of terms
tfidf_keyword = calculate_tf_idf2(doc_keyword);
tfidf_abstract = calculate_tf_idf2(doc_abstract);
tfidf_title = calculate_tf_idf2(doc_title);

-- calculate weighted results
tfidf_all_joined_A1 = JOIN doc_term_distinct BY (docId, term) LEFT OUTER, tfidf_abstract BY (docId, term);
tfidf_all_joined_A = FOREACH tfidf_all_joined_A1 GENERATE doc_term_distinct::docId AS docId, doc_term_distinct::term AS term, tfidf AS tfidfAbstract;
tfidf_all_joined_AK1 = JOIN tfidf_all_joined_A BY (docId, term) LEFT OUTER, tfidf_keyword BY (docId, term);
tfidf_all_joined_AK = FOREACH tfidf_all_joined_AK1 GENERATE tfidf_all_joined_A::docId AS docId, tfidf_all_joined_A::term AS term, tfidfAbstract, tfidf AS tfidfKeyword;
tfidf_all_joined_AKT1 = JOIN tfidf_all_joined_AK BY (docId, term) LEFT OUTER, tfidf_title BY (docId, term);
tfidf_all_joined_AKT = FOREACH tfidf_all_joined_AKT1 GENERATE tfidf_all_joined_AK::docId AS docId, tfidf_all_joined_AK::term AS term, tfidfAbstract, tfidfKeyword, tfidf AS tfidfTitle;

-- calculate weighted tfidf
tfidf_all_joined = FOREACH tfidf_all_joined_AKT GENERATE 
	docId, term, 
	WeightedTFIDF($KEYWORD_WEIGHT, tfidfKeyword, $TITLE_WEIGHT, tfidfTitle, $ABSTRACT_WEIGHT, tfidfAbstract) AS tfidf;

-- order relations by term before storing
tfidf_keyword_ord = ORDER tfidf_keyword BY term;
tfidf_abstract_ord = ORDER tfidf_abstract BY term;
tfidf_title_ord = ORDER tfidf_title BY term;
tfidf_all_ord = ORDER tfidf_all_joined BY term;

-- store into separate direcotires
STORE tfidf_keyword_ord INTO '$outputPath$KEYWORD_SUBDIR';
STORE tfidf_abstract_ord INTO '$outputPath$TITLE_SUBDIR';
STORE tfidf_title_ord INTO '$outputPath$ABSTRACT_SUBDIR';
STORE tfidf_all_ord INTO '$outputPath$JOINED_SUBDIR';
