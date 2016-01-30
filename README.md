# ElasticSearchService-cfc

### DESCRIPTION
CFML wrapper for interacting with Elastic Search. Supports Elastic Search's REST API and TCP connections via Elastic Search's TransportClient.

### SUPPORTED CFML ENGINES
* Adobe ColdFusion 9.0.1
* Adobe ColdFusion 10
* Adobe ColdFusion 11
* Lucee 4.5

### REQUIRED DEPENDENCIES (HTTP OR TCP)
* [Response.cfc](https://github.com/wellercs/Response-cfc)

### REQUIRED DEPENDENCIES FOR TCP
* elasticsearch jar
* lucene-core jar

### OPTIONAL DEPENDENCIES FOR TCP
* [JavaLoader](https://github.com/markmandel/JavaLoader)

### ASSUMPTIONS
* aggregation results must use key name `aggregation_results`
* aggregation hits must use key name `agg_hits`

### Service Constructor when using HTTP
```
ElasticSearchService = new ElasticSearchService(
	api_base_uri=""
);
```

### Service Constructor when using TCP without JavaLoader
```
ElasticSearchService = new ElasticSearchService(
	cluster_name="",
	master_node=""
);
```

### Service Constructor when using TCP with JavaLoader
```
ElasticSearchService = new ElasticSearchService(
	cluster_name="",
	master_node="",
	javaloaderMapping="",
	loadPaths=[
		"path/to/elasticsearch-1.6.0.jar",
		"path/to/lucene-core-4.10.4.jar"
	]
);
```

### Search Example
```
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
response = ElasticSearchService.suggest(
	context_field_name = "brand_id",
	context_field_value = "123",
	index = "dev",
	size = 10,
	text='My Awesome Product',
	fuzziness="auto"		
);
```

### Basic Query String Search Example
```
{
	"timeout": 30,
	"_source": ["label", "retail_unit_price"],
	"from": 0,
	"size": 10,
	"sort": [{
		"retail_unit_price": {
			"order": "asc"
		}
	}, {
		"label": {
			"order": "asc"
		}
	}],
	"query": {
		"filtered": {
			"filter": {
				"and": [{
					"bool": {
						"must": {
							"term": {
								"store_group_id": 9
							}
						}
					}
				}, {
					"bool": {
						"must": {
							"range": {
								"date_expected": {
									"lte": "2016-01-27"
								}
							}
						}
					}
				}, {
					"bool": {
						"should": {
							"term": {
								"default_product_category_id": 97
							}
						}
					}
				}]
			}
		}
	}
}
```

### Aggregation Query String Search Example
```
{
	"timeout": 30,
	"_source": [],
	"from": 0,
	"size": 10,
	"sort": [{
		"retail_unit_price": {
			"order": "asc"
		}
	}, {
		"label": {
			"order": "asc"
		}
	}],
	"query": {
		"filtered": {
			"filter": {
				"and": [{
					"bool": {
						"must": {
							"term": {
								"brand_id": 123
							}
						}
					}
				}
			}
		}
	},
	"aggs": {
		"aggregation_results": {
			"terms": {
				"field": "label",
				"collect_mode": "depth_first",
				"min_doc_count": 1,
				"shard_min_doc_count": 0,
				"size": 10,
				"order": [{
					"retail_unit_price": "asc"
				}, {
					"label": "asc"
				}]
			},
			"aggs": {
				"agg_hits": {
					"top_hits": {
						"_source": [],
						"size": 1,
						"sort": [{
							"retail_unit_price": {
								"order": "asc"
							}
						}, {
							"label": {
								"order": "asc"
							}
						}]
					}
				},
				"retail_unit_price": {
					"min": {
						"script": "doc.retail_unit_price"
					}
				},
				"label": {
					"min": {
						"script": "doc.label"
					}
				}
			}
		}
	}
}
```
