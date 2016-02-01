component {
	this.name = "ElasticSearchService";

    /**
    * @hint I initialize the component.
    * @api_base_uri I am the base URI of the API.
    * @http_port I am the port number to use for the REST API.
    * @cluster_name I am the cluster name.
    * @master_node I am the master node.
    * @tcp_port I am the port number to use for TCP communication.
    * @javaloaderMapping I am the mapping to the JavaLoader object.
    * @loadPaths An array of directories of classes, or paths to .jar files to load.
    * @loadColdFusionClassPath Determines whether to load the ColdFusion libraries with the loaded libraries.
    */
	function init(
		string api_base_uri = "",
		numeric http_port = 9200,
		string cluster_name = "",
		string master_node = "",
		numeric tcp_port = 9300,
		string javaloaderMapping = "",
		array loadPaths = [],
		boolean loadColdFusionClassPath = false
	) {
		variables.api_base_uri = arguments.api_base_uri;
		variables.http_port = arguments.http_port;
		variables.cluster_name = arguments.cluster_name;
		variables.master_node = arguments.master_node;
		variables.tcp_port = arguments.tcp_port;

		local.loadJars = false;
		if ( len(trim(arguments.javaloaderMapping)) OR (len(trim(arguments.cluster_name)) AND len(trim(arguments.master_node))) ) {
			local.loadJars = true;
		}

		if ( local.loadJars ) {
			local.jars = [
				{ name="jImmutableSettings", path="org.elasticsearch.common.settings.ImmutableSettings" },
				{ name="jInetSocketTransportAddress", path="org.elasticsearch.common.transport.InetSocketTransportAddress" },
				{ name="jElasticSearchSettings", path="org.elasticsearch.common.settings.Settings" },
				{ name="jTransportClient", path="org.elasticsearch.client.transport.TransportClient" },
				{ name="jFuzzinessUnit", path="org.elasticsearch.common.unit.Fuzziness" },
				{ name="jCompletionSuggestionFuzzyBuilder", path="org.elasticsearch.search.suggest.completion.CompletionSuggestionFuzzyBuilder" }
			];

			if ( len(trim(arguments.javaloaderMapping)) ) {
				variables.JavaLoader = new "#arguments.javaloaderMapping#"(arguments.loadPaths, arguments.loadColdFusionClassPath);
				for ( local.jar in local.jars ) {
					variables[local.jar.name] = variables.JavaLoader.create(local.jar.path);
				}
			}
			else {
				for ( local.jar in local.jars ) {
					variables[local.jar.name] = createObject("java", local.jar.path);
				}
			}

			variables.jInetAddress = createObject("java", "java.net.InetAddress");

			variables.ElasticSearchSettings = variables.jImmutableSettings.settingsBuilder()
																		.put("client.transport.sniff", true)
																		.put("cluster.name", variables.cluster_name)
																		.build();

			variables.ElasticSearchTransportClient = variables.jTransportClient.init(variables.ElasticSearchSettings)
																.addTransportAddress(variables.jInetSocketTransportAddress.init(variables.jInetAddress.getByName(variables.master_node).getHostAddress(), variables.tcp_port));

			// close all resources
			//client.close()

			// release the thread pool
			//client.threadPool().shutdown()
		}

		return this;
	}

    /**
    * @hint I am the search function.
    * @index I am the name of the search index.
    * @type I am the name of the search type.
    * @query_string I am the search query string in JSON format. Mustache example: getMustacheService().render(template=FileRead(getDirectoryFromPath(getCurrentTemplatePath()) & "/my_search_template.txt"), context=arguments)
    * @charset I am the charset of the HTTP request.
    * @method I am the HTTP method.
    * @protocol I am the protocol (TCP or HTTP) to use.
    * @search_type I am the search type when using the REST API.
    * @timeout I am the timeout limit for the request.
    */
	function search(
		required string index,
		required string type,
		required string query_string,
		string charset = "UTF-8",
		string method = "POST",
		string protocol = "TCP",
		string search_type = "query_then_fetch",
		string timeout = 30
	) {
		local.ResponseObj = new Response();

		local.return_data = {};

		local.request_start_tick_count = getTickCount();

		try {
			structAppend(arguments, deserializeJSON(arguments.query_string), true);

			local.return_data["input"]["index"] = arguments.index;
			local.return_data["input"]["type"] = arguments.type;
			local.return_data["input"]["query_string"] = arguments.query_string;
			local.return_data["input"]["protocol"] = arguments.protocol;

			if ( arguments.protocol IS "TCP" ) {
				local.indices = [];
				arrayAppend(local.indices, arguments.index);

				local.types = [];
				arrayAppend(local.types, arguments.type);

				local.TransportClientSearchRequest = variables.ElasticSearchTransportClient.prepareSearch(local.indices)
																							.setTypes(local.types)
																							;

				local.ElasticSearchResponse = local.TransportClientSearchRequest.setSource(arguments.query_string).execute().actionGet();

				local.handled_response = handleTCPSearchResponse(
											search_params = arguments,
											search_request = local.TransportClientSearchRequest,
											response = local.ElasticSearchResponse
										);
			}
			else {
				local.return_data["input"]["charset"] = arguments.charset;
				local.return_data["input"]["method"] = arguments.method;
				local.return_data["input"]["search_type"] = arguments.search_type;
				local.return_data["input"]["timeout"] = arguments.timeout;

				local.ElasticSearchResponse = makeHTTPRequest(
												httpURL = "#variables.api_base_uri#:#variables.http_port#/#arguments.index#/#arguments.type#/_search?search_type=#arguments.search_type#",
												httpProperties = {
													charset = arguments.charset,
													method = arguments.method,
													timeout = arguments.timeout
												},
												httpBodyParameter = arguments.query_string
											);

				if ( NOT local.ElasticSearchResponse.getSuccess() ) {
					return local.ElasticSearchResponse;
				}

				local.handled_response = handleHTTPSearchResponse(
											search_params = arguments,
											response = local.ElasticSearchResponse
										);
			}

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
    * @hint I handle the HTTP search response.
    * @search_params I am the arguments from the search function.
    * @response I am the response from the HTTP search request.
    */
	private function handleHTTPSearchResponse(
		required struct search_params,
		required any response
	) {
		local.ResponseObj = new Response();

		local.request_start_tick_count = getTickCount();

		local.return_data = {};
		local.return_data["input"] = {};
		local.return_data["output"] = {};
		local.return_data["input"]["requestprotocol"] = "HTTP";
		local.return_data["input"]["requestbody"] = arguments.response.getData().requestData.httpParameters.httpBodyParameter;
		local.return_data["input"]["requestmethod"] = arguments.response.getData().requestData.httpProperties.method;
		local.return_data["input"]["requesturl"] = arguments.response.getData().requestData.httpProperties.url;
		local.return_data["output"]["recordcount"] = arguments.response.getData().parsedFileContent.hits.total;
		if ( structKeyExists(arguments.response.getData(), "parsedFileContent") AND structKeyExists(arguments.response.getData().parsedFileContent, "aggregations") ) {
			local.agg = {};
			local.aggs = [];
			local.agg_len = arrayLen(arguments.response.getData().parsedFileContent.aggregations.aggregation_results.buckets); // TODO: make aggregation_results dynamic
			for ( local.a = 1; local.a <= local.agg_len; local.a++ ) {
				local.agg = arguments.response.getData().parsedFileContent.aggregations.aggregation_results.buckets[local.a]; // TODO: make aggregation_results dynamic
				if ( structKeyExists(local.agg, "agg_hits") ) {
					arrayAppend(local.aggs, local.agg.agg_hits.hits.hits[1]); // TODO: make agg_hits dynamic
				}
				else if ( structKeyExists(local.agg, "key") ) {
					arrayAppend(local.aggs, {"_id"=local.agg.key});
				}
			}
			local.return_data["output"]["results"] = local.aggs;
		}
		else {
			local.return_data["output"]["results"] = arguments.response.getData().parsedFileContent.hits.hits;
		}

		if ( arguments.response.getSuccess() ) {
			local.return_data["output"]["response_took"] = arguments.response.getRequestDurationInMilliseconds() - arguments.response.getData().httpSendTook;
			local.return_data["output"]["send_took"] = arguments.response.getData().httpSendTook;
			local.return_data["output"]["timed_out"] = arguments.response.getData().parsedFileContent.timed_out;
			local.return_data["output"]["took"] = arguments.response.getData().parsedFileContent.took;
		}

		local.ResponseObj.setSuccess(arguments.response.getSuccess());
		local.ResponseObj.setErrorMessage(arguments.response.getErrorMessage());
		local.ResponseObj.setStatusText(arguments.response.getStatusText());
		local.ResponseObj.setStatusCode(arguments.response.getStatusCode());
		local.ResponseObj.setData(local.return_data);

		local.ResponseObj.setRequestDurationInMilliseconds( getTickCount() - local.request_start_tick_count );

		local.return_data["output"]["response_handling_took"] = local.ResponseObj.getRequestDurationInMilliseconds();

		return local.ResponseObj;
	}

    /**
    * @hint I handle the TCP search response.
    * @search_params I am the arguments from the search function.
    * @search_request I am the transport client search request object.
    * @response I am the response from the transport client search request.
    */
	private function handleTCPSearchResponse(
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
			local.agg = {};
			local.aggs = [];
			local.agg_len = arrayLen(local.response_struct.aggregations.aggregation_results.buckets); // TODO: make aggregation_results dynamic
			for ( local.a = 1; local.a <= local.agg_len; local.a++ ) {
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
    * @charset I am the charset of the HTTP request.
    * @method I am the HTTP method.
    * @fuzziness I am the fuzziness factor.
    * @protocol I am the protocol (TCP or HTTP) to use.
    * @timeout I am the timeout limit for the request.
    */
	function suggest(
		required string context_field_name,
		required string context_field_value,
		required string index,
		required numeric size,
		required string text,
		string charset = "UTF-8",
		string method = "POST",
		any fuzziness = "auto",
		string protocol = "TCP",
		string suggestion_field = "suggest",
		string timeout = 3
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
			local.return_data["input"]["suggestion_field"] = arguments.suggestion_field;

			if ( arguments.protocol IS "TCP" ) {
				variables.jCompletionSuggestionFuzzyBuilder.init(arguments.suggestion_field);
				variables.jCompletionSuggestionFuzzyBuilder.size(arguments.size);
				variables.jCompletionSuggestionFuzzyBuilder.setFuzziness(variables.jFuzzinessUnit[UCase(arguments.fuzziness)]);
				variables.jCompletionSuggestionFuzzyBuilder.addContextField(arguments.context_field_name, [javaCast("string", arguments.context_field_value)]);

				local.indices = [];
				arrayAppend(local.indices, arguments.index);

				local.SuggestRequestBuilder = variables.ElasticSearchTransportClient.prepareSuggest(local.indices);
				local.SuggestRequestBuilder.setSuggestText(arguments.text);
				local.SuggestRequestBuilder.addSuggestion(variables.jCompletionSuggestionFuzzyBuilder.field(arguments.suggestion_field));

				local.SuggestResponse = local.SuggestRequestBuilder.execute().actionGet();

				local.handled_response = handleTCPSuggestResponse(
											suggest_request = local.SuggestRequestBuilder,
											response = local.SuggestResponse,
											suggestion_field = arguments.suggestion_field
										);
			}
			else {
				local.ElasticSearchResponse = makeHTTPRequest(
												httpURL = "#variables.api_base_uri#:#variables.http_port#/#arguments.index#/_suggest",
												httpProperties = {
													charset = arguments.charset,
													method = arguments.method,
													timeout = arguments.timeout
												},
												httpBodyParameter = buildSuggestQueryString(
																		context_field_name = arguments.context_field_name,
																		context_field_value = arguments.context_field_value,
																		fuzziness = arguments.fuzziness,
																		size = arguments.size,
																		suggestion_field = arguments.suggestion_field,
																		text = arguments.text
																	)
											);

				if ( NOT local.ElasticSearchResponse.getSuccess() ) {
					return local.ElasticSearchResponse;
				}

				local.handled_response = handleHTTPSuggestResponse(
											response = local.ElasticSearchResponse
										);
			}

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
	* @hint I build the JSON query string for the suggest API.
	* @context_field_name I am the name of the context field.
    * @context_field_value I am the value of the context field.
    * @fuzziness I am the fuzziness factor.
    * @size I am the number of items to return.
    * @suggestion_field I am the name of the suggestion field.
    * @text I am the text string.
	*/
	private function buildSuggestQueryString(
		required string context_field_name,
		required string context_field_value,
		required string fuzziness,
		required numeric size,
		required string suggestion_field,
		required string text
	) {
		return '{"suggestions":{"text":"#arguments.text#","completion":{"field":"#arguments.suggestion_field#","size":#arguments.size#,"fuzzy":{"fuzziness":"#arguments.fuzziness#"},"context":{"#arguments.context_field_name#":"#arguments.context_field_value#"}}}}';
	}

    /**
    * @hint I handle the HTTP suggest response.
    * @response I am the response from the HTTP suggest request.
    */
	private function handleHTTPSuggestResponse(
		required any response
	) {
		local.ResponseObj = new Response();

		local.request_start_tick_count = getTickCount();

		local.return_data = {};
		local.return_data["input"] = {};
		local.return_data["output"] = {};
		local.return_data["input"]["requestprotocol"] = "HTTP";
		local.return_data["input"]["requestbody"] = arguments.response.getData().requestData.httpParameters.httpBodyParameter;
		local.return_data["input"]["requestmethod"] = arguments.response.getData().requestData.httpProperties.method;
		local.return_data["input"]["requesturl"] = arguments.response.getData().requestData.httpProperties.url;
		local.return_data["output"]["recordcount"] = arrayLen(arguments.response.getData().parsedFileContent.suggestions[1].options);
		local.return_data["output"]["results"] = arguments.response.getData().parsedFileContent.suggestions[1].options;

		if ( arguments.response.getSuccess() ) {
			local.return_data["output"]["response_took"] = arguments.response.getRequestDurationInMilliseconds() - arguments.response.getData().httpSendTook;
			local.return_data["output"]["send_took"] = arguments.response.getData().httpSendTook;
		}

		local.ResponseObj.setSuccess(arguments.response.getSuccess());
		local.ResponseObj.setErrorMessage(arguments.response.getErrorMessage());
		local.ResponseObj.setStatusText(arguments.response.getStatusText());
		local.ResponseObj.setStatusCode(arguments.response.getStatusCode());
		local.ResponseObj.setData(local.return_data);

		local.ResponseObj.setRequestDurationInMilliseconds( getTickCount() - local.request_start_tick_count );

		local.return_data["output"]["response_handling_took"] = local.ResponseObj.getRequestDurationInMilliseconds();

		return local.ResponseObj;
	}

    /**
    * @hint I handle the TCP suggest response.
    * @suggest_request I am the suggest request object.
    * @response I am the response from the transport client suggest request.
    * @suggestion_field I am the suggestion field.
    */
	private function handleTCPSuggestResponse(
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

	/**
	* @hint I make the HTTP request to the API.
	*/
	private function makeHTTPRequest(
		required string httpURL,
		struct httpProperties = {},
		struct httpHeaderParameters = {},
		struct httpCGIParameters = {},
		string httpBodyParameter = "",
		struct httpXMLParameters = {},
		struct httpFileParameters = {},
		struct httpURLParameters = {},
		struct httpFormFieldParameters = {},
		struct httpCookieParameters = {},
		boolean logFlag = true,
		string format = "component"
	) {
		local.ResponseObj = new Response();
		local.responseData = {};

		local.request_start_tick_count = GetTickCount();

		try {
			local.httpService = new http();

			local.httpService.setURL(arguments.httpURL);

			// TODO: use this for CF10+
			// for ( local.httpProperty in arguments.httpProperties ) {
			// 	invoke(local.httpService, "set#local.httpProperty#", {"#local.httpProperty#"=arguments.httpProperties[local.httpProperty]});
			// }

			// BEGIN: remove this block for CF10+
			if ( structKeyExists(arguments.httpProperties, "charset") ) {
				local.httpService.setcharset(arguments.httpProperties.charset);
			}
			if ( structKeyExists(arguments.httpProperties, "method") ) {
				local.httpService.setmethod(arguments.httpProperties.method);
			}
			if ( structKeyExists(arguments.httpProperties, "password") ) {
				local.httpService.setpassword(arguments.httpProperties.password);
			}
			if ( structKeyExists(arguments.httpProperties, "timeout") ) {
				local.httpService.settimeout(arguments.httpProperties.timeout);
			}
			if ( structKeyExists(arguments.httpProperties, "username") ) {
				local.httpService.setusername(arguments.httpProperties.username);
			}
			// END: remove this block for CF10+

			for ( local.httpHeaderParameter in arguments.httpHeaderParameters ) {
				local.httpService.addParam(type="header", name=local.httpHeaderParameter, value=arguments.httpHeaderParameters[local.httpHeaderParameter]);
			}
			for ( local.httpCGIParameter in arguments.httpCGIParameters ) {
				local.httpService.addParam(type="CGI", name=local.httpCGIParameter, value=arguments.httpCGIParameters[local.httpCGIParameter]);
			}
			if ( len(trim(arguments.httpBodyParameter)) ) {
				local.httpService.addParam(type="body", name="body", value=arguments.httpBodyParameter);
			}
			for ( local.httpXMLParameter in arguments.httpXMLParameters ) {
				local.httpService.addParam(type="XML", name=local.httpXMLParameter, value=arguments.httpXMLParameters[local.httpXMLParameter]);
			}
			for ( local.httpFileParameter in arguments.httpFileParameters ) {
				local.httpService.addParam(type="file", name=local.httpFileParameter, file=arguments.httpFileParameters[local.httpFileParameter]);
			}
			for ( local.httpURLParameter in arguments.httpURLParameters ) {
				local.httpService.addParam(type="URL", name=local.httpURLParameter, value=arguments.httpURLParameters[local.httpURLParameter]);
			}
			for ( local.httpFormFieldParameter in arguments.httpFormFieldParameters ) {
				local.httpService.addParam(type="formField", name=local.httpFormFieldParameter, value=arguments.httpFormFieldParameters[local.httpFormFieldParameter]);
			}
			for ( local.httpCookieParameter in arguments.httpCookieParameters ) {
				local.httpService.addParam(type="cookie", name=local.httpCookieParameter, value=arguments.httpCookieParameters[local.httpCookieParameter]);
			}

			local.request_data = {};
			local.request_data.httpProperties = local.httpService.getAttributes();
			local.request_data.httpParameters.httpHeaderParameters = arguments.httpHeaderParameters;
			local.request_data.httpParameters.httpCGIParameters = arguments.httpCGIParameters;
			local.request_data.httpParameters.httpBodyParameter = arguments.httpBodyParameter;
			local.request_data.httpParameters.httpXMLParameters = arguments.httpXMLParameters;
			local.request_data.httpParameters.httpFileParameters = arguments.httpFileParameters;
			local.request_data.httpParameters.httpURLParameters = arguments.httpURLParameters;
			local.request_data.httpParameters.httpFormFieldParameters = arguments.httpFormFieldParameters;
			local.request_data.httpParameters.httpCookieParameters = arguments.httpCookieParameters;
			local.responseData.requestData = local.request_data;
			local.request_data = serializeJSON(local.request_data);

			local.http_start_tick_count = GetTickCount();

			local.httpResult = local.httpService.send().getPrefix();

			local.http_end_tick_count = GetTickCount();
			local.http_duration_in_milliseconds = local.http_end_tick_count - local.http_start_tick_count;

			if ( NOT isDefined("local.httpResult.Responseheader.Status_Code") ) {
				local.httpResult["Responseheader"]["Status_Code"] = 0;
				local.httpResult["Responseheader"]["Explanation"] = local.httpResult.Statuscode;
				if ( isDefined("local.httpResult.Statuscode") AND arrayLen(REMatch("^[\d]+", local.httpResult.Statuscode)) ) {
					local.httpResult["Responseheader"]["Status_Code"] = REMatch("^[\d]+", local.httpResult.Statuscode)[1];
					local.httpResult["Responseheader"]["Explanation"] = Trim(Replace(local.httpResult.Statuscode, local.httpResult["Responseheader"]["Status_Code"], "", "one"));
				}
			}

			if ( arguments.logFlag ) {
				try {
					// log
				} catch (any e) {
					// ignore
				}
			}

			local.responseData.httpSendTook = local.http_duration_in_milliseconds;
			local.responseData.httpURL = arguments.httpURL;
			local.responseData.httpResult = local.httpResult;
			local.responseData.rawFileContent = local.httpResult.Filecontent;
			if ( IsJSON(local.responseData.rawFileContent) ) {
				local.responseData.parsedFileContent = deserializeJSON(local.responseData.rawFileContent);
			}
			else if ( IsXML(local.responseData.rawFileContent) ) {
				local.responseData.parsedFileContent = xmlParse(local.responseData.rawFileContent);
			}
			else if ( IsSimpleValue(local.responseData.rawFileContent) ) {
				local.fileContentArray = listToArray(local.responseData.rawFileContent, "&");
				for ( local.fileContentItem in local.fileContentArray ) {
					local.fileContentItemKey = listFirst(local.fileContentItem, "=");
					local.fileContentItemValue = listLast(local.fileContentItem, "=");
					local.responseData.parsedFileContent[local.fileContentItemKey] = local.fileContentItemValue;
				}
			}

			local.ResponseObj.setData(local.responseData);

			if ( local.httpResult.Responseheader.Status_Code <= 206 && local.httpResult.Responseheader.Status_Code >= 200 ) {
				// most status codes will be 200 so this is just a placeholder to speed up the condition check
			}
			else {
				local.ResponseObj.setSuccess(false);
				local.ResponseObj.setErrorCode(2);
				local.ResponseObj.setErrorMessage("Error making http request.");
				local.ResponseObj.setErrorDetail(local.httpResult.ErrorDetail);
				local.ResponseObj.setStatusCode(local.httpResult.Responseheader.Status_Code);
				local.ResponseObj.setStatusText(local.httpResult.Responseheader.Explanation);
			}
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
		}

        local.request_duration_in_milliseconds = GetTickCount() - local.request_start_tick_count;

        local.ResponseObj.setRequestDurationInMilliseconds(local.request_duration_in_milliseconds);

		return local.ResponseObj.getResponse(format=arguments.format);
	}
}