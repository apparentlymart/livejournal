/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership. The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */

/**
 * Provide a transport of osapi requests over JSON-RPC. Exposed JSON-RPC endpoints and
 * their associated methods are available from config in the "osapi.services" field.
 */
(function() {

  var useOAuth2;

  /**
   * Called by a batch to execute all requests
   * @param {Object} requests
   * @param {function(Object)} callback
   */
  function execute(requests, callback, st) {
    function processResponse(response) {
      // Convert an XHR failure to a JSON-RPC error
      if (response['errors'][0]) {
        callback({
          error: {
            'code': response['rc'],
            'message': response['text']
          }
        });
      } else {
        var jsonResponse = response['result'] || response['data'];
        if (jsonResponse['error']) {
          callback(jsonResponse);
        } else {
          var responseMap = {};
          for (var i = 0; i < jsonResponse.length; i++) {
            responseMap[jsonResponse[i]['id']] = jsonResponse[i];
          }
          callback(responseMap);
        }
      }
    }

    var request = {
      'POST_DATA' : gadgets.json.stringify(requests),
      'CONTENT_TYPE' : 'JSON',
      'METHOD' : 'POST',
      'AUTHORIZATION' : 'SIGNED'
    };
    var headers = {'Content-Type': 'application/json'};

    var url = this.name;
    var token = st;
    if (token) {
      if (useOAuth2) {
        headers['Authorization'] = 'OAuth2 ' + token;
      } else {
        url += '?st=';
        url += encodeURIComponent(token);
      }
    }
    gadgets.io.makeNonProxiedRequest(url, processResponse, request, headers);
  }

  function init(config) {
    var services = config['osapi.services'];
    useOAuth2 = config['osapi.useOAuth2'];
    if (services) {
      // Iterate over the defined services, extract the http endpoints and
      // create a transport per-endpoint
      for (var endpointName in services) {
        if (services.hasOwnProperty(endpointName)) {
          if (endpointName.indexOf('http') == 0 ||
              endpointName.indexOf('//') == 0) {
            // Expand the host & append the security token
            var endpointUrl = endpointName.replace('%host%', document.location.host);
            var transport = { 'name' : endpointUrl, 'execute' : execute };
            var methods = services[endpointName];
            for (var i = 0; i < methods.length; i++) {
              osapi._registerMethod(methods[i], transport);
            }
          }
        }
      }
    }
  }

  // We do run this in the container mode in the new common container
  if (gadgets.config) {
    gadgets.config.register('osapi.services', null, init);
  }

})();
