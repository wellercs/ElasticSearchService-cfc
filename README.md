# ElasticSearchService-cfc

### DESCRIPTION
CFML wrapper for interacting with Elastic Search. Currently uses TCP connections via Elastic Search's TransportClient. REST API support coming soon.

### SUPPORTED CFML ENGINES
* Adobe ColdFusion 9.0.1

### DEPENDENCIES
* elasticsearch jar
* lucene-core jar
* [Response.cfc](https://github.com/wellercs/Response-cfc)

### ASSUMPTIONS
* aggregation results must use key name `aggregation_results`
* aggregation hits must use key name `agg_hits`

### Search Example
```
ElasticSearchService = new ElasticSearchService(cluster_name="", master_node="");
response = ElasticSearchService.search(
	index = "dev",
	type = "product",
	page = 1,
	size = 10,
	query_string = '{"timeout": 30,"_source": ["label","retail_unit_price"],"from": 0,"size": 10,"sort":[{"retail_unit_price": {"order": "asc"}},{"label": {"order": "asc"}}],"query":{"filtered":{"filter":{"and":[{"bool":{"must":{"term":{"store_group_id":9}}}},{"bool":{"must":{"range":{"date_expected":{"lte":"2016-01-27"}}}}},{"bool":{"should":{"term":{"default_product_category_id":97}}}}]}}}}'		
);
```

### Suggest Example
```
ElasticSearchService = new ElasticSearchService(cluster_name="", master_node="");
response = ElasticSearchService.suggest(
	context_field_name = "brand_id",
	context_field_value = "123",
	index = "dev",
	size = 10,
	text='My Awesome Product',
	fuzziness="auto"		
);
```
