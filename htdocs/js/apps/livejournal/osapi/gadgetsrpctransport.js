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
 * A transport for osapi based on gadgets.rpc. Allows osapi to expose APIs requiring container
 * and user UI mediation in addition to allowing data oriented APIs to be implemented using
 * gadgets.rpc instead of XHR/JSON-RPC/REST etc..
 */
if (gadgets && gadgets.rpc) { //Dont bind if gadgets.rpc not defined
  (function() {

    /**
     * Execute the JSON-RPC batch of gadgets.rpc. The container is expected to implement
     * the method osapi._handleGadgetRpcMethod(<JSON-RPC batch>)
     *
     * @param {Object} requests the opensocial JSON-RPC request batch.
     * @param {function(Object)} callback to the osapi batch with either an error response or
     * a JSON-RPC batch result.
     * @private
     */
    function execute(requests, callback) {
      var rpcCallback = function(response) {
        if (!response) {
          callback({ 'code': 500, 'message': 'Container refused the request' });
        } else if (response['error']) {
          callback(response);
        } else {
          var responseMap = {};
          for (var i = 0; i < response.length; i++) {
            responseMap[response[i]['id']] = response[i];
          }
          callback(responseMap);
        }
      };
      //we add here our security token because all json-rpc requests are made
      //on the container side now
      gadgets.rpc.call('..', 'osapi._handleGadgetRpcMethod', rpcCallback, requests,
              livejournal.getSecurityToken().getToken());
      // TODO - Timeout handling if rpc silently fails?
    }

    function init(config) {
      var transport = { 'name': 'gadgets.rpc', 'execute' : execute };
      var services = config['osapi.services'];
      if (services) {
        // Iterate over the defined services, extract the gadget.rpc endpoint and
        // bind to it
        for (var endpointName in services) {
          if (services.hasOwnProperty(endpointName)) {
            if (endpointName === 'gadgets.rpc') {
              var methods = services[endpointName];
              for (var i = 0; i < methods.length; i++) {
                osapi._registerMethod(methods[i], transport);
              }
            }
          }
        }
      }

      // Check if the container.listMethods is bound? If it is then use it to
      // introspect the container services for available methods and bind them
      // Because the call is asynchronous we delay the execution of the gadget onLoad
      // handler until the callback has completed. Containers wishing to avoid this
      // behavior should not specify a binding for container.listMethods in their
      // container config but rather list out all the container methods they want to
      // expose directly which is the preferred option for production environments
      if (osapi.container && osapi.container.listMethods) {

        // Intercept the onload handler so that it is not called until
        // - gadgets.util.runOnLoadHandlers called at end of gadget,
        //   and either
        //   - callback from container.listMethods
        //   - callback from window.setTimeout
        var originalRunOnLoadHandlers = gadgets.util.runOnLoadHandlers;
        var gadgetFlag = false;
        var listMethodsFlag = false;
        var triggered = false;
        var trigger = function() {
          if (!triggered && gadgetFlag && listMethodsFlag) {
            triggered = true;
            originalRunOnLoadHandlers();
          }
        };
        gadgets.util.runOnLoadHandlers = function() {
          gadgetFlag = true;
          trigger();
        };

        // Call for the container methods and bind them to osapi.
        osapi.container.listMethods({}).execute(function(response) {
          if (!response['error']) {
            for (var i = 0; i < response.length; i++) {
              // do not rebind container.listMethods implementation
              if (response[i] != 'container.listMethods') {
                osapi._registerMethod(response[i], transport);
              }
            }
          }
          listMethodsFlag = true;
          trigger();
        });

        // Wait 500ms for the rpc. This should be a reasonable upper bound
        // even for slow transports while still allowing for reasonable testing
        // in a development environment
        window.setTimeout(function() {
          listMethodsFlag = true;
          trigger();
        }, 500);
      }
    }

    // Do not run this in container mode.
    if (gadgets.config) {
      gadgets.config.register('osapi.services', null, init);
    }
  })();
}
