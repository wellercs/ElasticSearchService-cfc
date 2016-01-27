component {
	this.name = "ElasticSearchService";

    /**
    * @hint I initialize the component.
    * @cluster_name I am the cluster name.
    * @master_node I am the master node.
    */
	function init(
		required string cluster_name,
		required string master_node
	) {
		variables.cluster_name = arguments.cluster_name;
		variables.master_node = arguments.master_node;

		variables.jImmutableSettings = createObject("java", "org.elasticsearch.common.settings.ImmutableSettings");
		variables.jInetAddress = createObject("java", "java.net.InetAddress");
		variables.jInetSocketTransportAddress = createObject("java", "org.elasticsearch.common.transport.InetSocketTransportAddress");
		variables.jElasticSearchSettings = createObject("java", "org.elasticsearch.common.settings.Settings");
		variables.jTransportClient = createObject("java", "org.elasticsearch.client.transport.TransportClient");
		variables.jFuzzinessUnit = createObject("java", "org.elasticsearch.common.unit.Fuzziness");
		variables.jCompletionSuggestionFuzzyBuilder = createObject("java", "org.elasticsearch.search.suggest.completion.CompletionSuggestionFuzzyBuilder");

		variables.ElasticSearchSettings = variables.jImmutableSettings.settingsBuilder()
																	.put("client.transport.sniff", true)
																	.put("cluster.name", variables.cluster_name)
																	.build();

		variables.ElasticSearchTransportClient = variables.jTransportClient.init(variables.ElasticSearchSettings)
															.addTransportAddress(variables.jInetSocketTransportAddress.init(variables.jInetAddress.getByName(variables.master_node).getHostAddress(), 9300));

		// close all resources
		//client.close()

		// release the thread pool
		//client.threadPool().shutdown()

		return this;
	}

    /**
    * @hint I am the search function.
    * @index I am the name of the search index.
    * @type I am the name of the search type.
    * @page I am the starting page.
    * @size I am the number of items in each page.
    * @query_string I am the search query string in JSON format. Mustache example: getMustacheService().render(template=FileRead(getDirectoryFromPath(getCurrentTemplatePath()) & "/my_search_template.txt"), context=arguments)
    */
	function search(
		required string index,
		required string type,
		required numeric page,
		required numeric size,
		required string query_string
	) {
		local.ResponseObj = new Response();

		local.return_data = {};

		local.request_start_tick_count = getTickCount();

		try {
			local.return_data["input"]["index"] = arguments.index;
			local.return_data["input"]["type"] = arguments.type;
			local.return_data["input"]["page"] = arguments.page;
			local.return_data["input"]["size"] = arguments.size;

			local.indices = [];
			arrayAppend(local.indices, arguments.index);

			local.types = [];
			arrayAppend(local.types, arguments.type);

			if ( arguments.page LTE 0 ) {
				arguments.page = 1;
			}

			arguments.from = (arguments.page * arguments.size) - (arguments.size - 1);

			if ( arguments.from LTE 0 ) {
				arguments.from = 1;
			}

			arguments.to = (arguments.page * arguments.size);

			arguments.agg_from = arguments.from;
			arguments.agg_to = arguments.to;

			// always return first page of agg results if agg_size is anything other than 0 to prevent array index not found error
			if ( NOT structKeyExists(arguments, "agg_size") OR arguments.agg_size NEQ 0 ) {
				arguments.agg_from = 1;
				arguments.agg_to = arguments.size;				
			}

			local.TransportClientSearchRequest = variables.ElasticSearchTransportClient.prepareSearch(local.indices)
																						.setTypes(local.types)
																						;

			local.ElasticSearchResponse = local.TransportClientSearchRequest.setSource(arguments.query_string).execute().actionGet();

			local.handled_response = handleSearchResponse(
										search_params = arguments,
										search_request = local.TransportClientSearchRequest,
										response = local.ElasticSearchResponse
									);

			structAppend(local.return_data, local.handled_response.getData(), true);
			local.return_data["output"]["pages"] = ceiling(local.return_data.output.recordcount / arguments.size);

			local.ResponseObj.setSuccess(local.handled_response.getSuccess());
			local.ResponseObj.setStatusText(local.handled_response.getStatusText());
			local.ResponseObj.setStatusCode(local.handled_response.getStatusCode());
			local.ResponseObj.setErrorMessage(local.handled_response.getErrorMessage());
		} catch (any e) {
			local.ResponseObj.setSuccess(false);
			local.ResponseObj.setErrorCode(1);
			if ( structKeyExists(e, "message") ) {
				local.ResponseObj.setErrorMessage(e.message);
			}
			if ( structKeyExists(e, "detail") ) {
				local.ResponseObj.setErrorDetail(e.detail);
			}
			if ( structKeyExists(e, "stacktrace") ) {
				local.ResponseObj.setStackTrace(e.stacktrace);
			}
			local.ResponseObj.setStatusCode(400);
			local.ResponseObj.setStatusText("Bad Request");
			local.return_data["output"]["results"] = [];			
		}

		local.ResponseObj.setRequestDurationInMilliseconds( getTickCount() - local.request_start_tick_count );

		local.ResponseObj.setData(local.return_data);

		return local.ResponseObj;
	}

    /**
    * @hint I handle the search response.
    * @search_params I am the arguments from the search function.
    * @search_request I am the transport client search request object.
    * @response I am the response from the transport client search request.
    */
	function handleSearchResponse(
		required struct search_params,
		required any search_request,
		required any response
	) {
		local.ResponseObj = new Response();

		local.request_start_tick_count = getTickCount();

		local.return_data = {};
		local.return_data["input"] = {};
		local.return_data["output"] = {};

		local.return_data["input"]["requeststring"] = arguments.search_request.toString();
		local.return_data["input"]["remotehostname"] = arguments.response.remoteAddress().address().getHostName();
		local.return_data["input"]["remoteport"] = arguments.response.remoteAddress().address().getPort();
		local.return_data["input"]["requestprotocol"] = "TCP";
		local.return_data["output"]["recordcount"] = arguments.response.getHits().getTotalHits();

		local.response_json = arguments.response.toString();
		local.response_struct = deserializeJSON(local.response_json);

		if ( isNull(arguments.response.getAggregations()) ) {
			local.return_data["output"]["results"] = local.response_struct.hits.hits;
		}
		else {
			// TOFIX: agg_from is undefined
			local.agg = {};
			local.aggs = [];
			local.agg_len = arrayLen(local.response_struct.aggregations.aggregation_results.buckets); // TODO: make aggregation_results dynamic
			for ( local.a = arguments.search_params.agg_from; local.a <= local.agg_len; local.a++ ) {
				local.agg = local.response_struct.aggregations.aggregation_results.buckets[local.a]; // TODO: make aggregation_results dynamic
				if ( structKeyExists(local.agg, "agg_hits") ) {
					arrayAppend(local.aggs, local.agg.agg_hits.hits.hits[1]); // TODO: make agg_hits dynamic
				}
				else if ( structKeyExists(local.agg, "key") ) {
					arrayAppend(local.aggs, {"_id"=local.agg.key});
				}
			}
			local.return_data["output"]["results"] = local.aggs;
		}

		if ( arguments.response.status().getStatus() EQ 200 ) {
			local.return_data["output"]["terminated_early"] = arguments.response.isTerminatedEarly();
			local.return_data["output"]["timed_out"] = arguments.response.isTimedOut();
			local.return_data["output"]["took"] = arguments.response.getTookInMillis();
		}
		else {
			local.ResponseObj.setSuccess(false);
		}

		local.ResponseObj.setStatusText(arguments.response.status().name());
		local.ResponseObj.setStatusCode(arguments.response.status().getStatus());
		local.ResponseObj.setData(local.return_data);
		local.ResponseObj.setRequestDurationInMilliseconds( getTickCount() - local.request_start_tick_count );

		local.return_data["output"]["response_handling_took"] = local.ResponseObj.getRequestDurationInMilliseconds();

		return local.ResponseObj;
	}

    /**
    * @hint I am the suggest function.
    * @context_field_name I am the name of the context field.
    * @context_field_value I am the value of the context field.
    * @index I am the name of the suggest index.
    * @size I am the number of items to return.
    * @text I am the text string.
    * @fuzziness I am the fuzziness factor.
    */
	function suggest(
		required string context_field_name,
		required string context_field_value,
		required string index,
		required numeric size,
		required string text,
		any fuzziness = "auto"
	) {
		local.ResponseObj = new Response();

		local.return_data = {};
		local.return_data["input"] = {};
		local.return_data["output"] = {};

		local.request_start_tick_count = getTickCount();

		try {
			// escape special characters to prevent undefined suggestions error
			arguments.text = replace(arguments.text, '\', '\\', 'all');
			arguments.text = replace(arguments.text, '"', '\"', 'all');

			local.return_data["input"]["context_field_name"] = arguments.context_field_name;
			local.return_data["input"]["context_field_value"] = arguments.context_field_value;
			local.return_data["input"]["index"] = arguments.index;
			local.return_data["input"]["size"] = arguments.size;
			local.return_data["input"]["text"] = arguments.text;
			local.return_data["input"]["fuzziness"] = arguments.fuzziness;

			local.suggestion_field = "suggest";

			variables.jCompletionSuggestionFuzzyBuilder.init(local.suggestion_field);
			variables.jCompletionSuggestionFuzzyBuilder.size(arguments.size);
			variables.jCompletionSuggestionFuzzyBuilder.setFuzziness(variables.jFuzzinessUnit[UCase(arguments.fuzziness)]);
			variables.jCompletionSuggestionFuzzyBuilder.addContextField(arguments.context_field_name, [javaCast("string", arguments.context_field_value)]);

			local.indices = [];
			arrayAppend(local.indices, arguments.index);

			local.SuggestRequestBuilder = variables.ElasticSearchTransportClient.prepareSuggest(local.indices);
			local.SuggestRequestBuilder.setSuggestText(arguments.text);
			local.SuggestRequestBuilder.addSuggestion(variables.jCompletionSuggestionFuzzyBuilder.field(local.suggestion_field));

			local.SuggestResponse = local.SuggestRequestBuilder.execute().actionGet();

			local.handled_response = handleSuggestResponse(
										suggest_request = local.SuggestRequestBuilder,
										response = local.SuggestResponse,
										suggestion_field = local.suggestion_field
									);

			structAppend(local.return_data, local.handled_response.getData(), true);
			local.return_data["output"]["pages"] = ceiling(local.return_data.output.recordcount / arguments.size);

			local.ResponseObj.setSuccess(local.handled_response.getSuccess());
			local.ResponseObj.setStatusText(local.handled_response.getStatusText());
			local.ResponseObj.setStatusCode(local.handled_response.getStatusCode());
			local.ResponseObj.setErrorMessage(local.handled_response.getErrorMessage());
		} catch (any e) {
			local.ResponseObj.setSuccess(false);
			local.ResponseObj.setErrorCode(1);
			if ( structKeyExists(e, "message") ) {
				local.ResponseObj.setErrorMessage(e.message);
			}
			if ( structKeyExists(e, "detail") ) {
				local.ResponseObj.setErrorDetail(e.detail);
			}
			if ( structKeyExists(e, "stacktrace") ) {
				local.ResponseObj.setStackTrace(e.stacktrace);
			}
			local.ResponseObj.setStatusCode(400);
			local.ResponseObj.setStatusText("Bad Request");
			local.return_data["output"]["results"] = [];	
		}

		local.ResponseObj.setRequestDurationInMilliseconds( getTickCount() - local.request_start_tick_count );

		local.ResponseObj.setData(local.return_data);

		return local.ResponseObj;
	}

    /**
    * @hint I handle the suggest response.
    * @suggest_request I am the suggest request object.
    * @response I am the suggest response object.
    * @suggestion_field I am the suggestion field.
    */
	private function handleSuggestResponse(
		required any suggest_request,
		required any response,
		required string suggestion_field
	) {
		local.ResponseObj = new Response();

		local.return_data = {};
		local.return_data["input"] = {};
		local.return_data["output"] = {};

		local.suggestions = [];
		local.SuggestRequestBuilder = arguments.suggest_request;
		local.SuggestResponse = arguments.response;
		local.Suggest = local.SuggestResponse.getSuggest();
		local.Suggestion = local.Suggest.getSuggestion(arguments.suggestion_field);
		local.SuggestionEntries = local.Suggestion.getEntries();

		for ( local.SuggestionEntry in local.SuggestionEntries ) {
			local.SuggestionEntryOptions = local.SuggestionEntry.getOptions();
			for ( local.SuggestionEntryOption in local.SuggestionEntryOptions ) {
				arrayAppend(
					local.suggestions,
					{
						"payload" = deserializeJSON(local.SuggestionEntryOption.getPayloadAsString()),
						"text" = local.SuggestionEntryOption.getText().toString()
					}
				);
			}
		}

		local.return_data["input"]["requeststring"] = local.SuggestRequestBuilder.request().toString();
		local.return_data["input"]["remotehostname"] = local.SuggestResponse.remoteAddress().address().getHostName();
		local.return_data["input"]["remoteport"] = local.SuggestResponse.remoteAddress().address().getPort();
		local.return_data["input"]["requestprotocol"] = "TCP";
		local.return_data["output"]["recordcount"] = arrayLen(local.suggestions);
		local.return_data["output"]["results"] = local.suggestions;
		local.return_data["output"]["results_json"] = local.SuggestResponse.getSuggest().toString();

		local.ResponseObj.setData(local.return_data);

		return local.ResponseObj;
	}
}