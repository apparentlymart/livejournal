/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership. The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License. You may obtain a copy of the License at
 *
 *		 http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */


/**
 * @fileoverview This represents the service layer that talks to OSAPI
 * endpoints. All RPC requests should go into this class.
 */


/**
 * @param {Object=} opt_config Configuration JSON.
 * @constructor
 */
osapi.container.Service = function(opt_config) {
	var config = this.config_ = opt_config || {};

	this.registerOsapiServices();

	this.onConstructed(config);
};


/**
 * Callback that occurs after instantiation/construction of this. Override to
 * provide your specific functionalities.
 * @param {Object=} opt_config Configuration JSON.
 */
osapi.container.Service.prototype.onConstructed = function(opt_config) {};


/**
 * Initialize OSAPI endpoint methods/interfaces.
 */
osapi.container.Service.prototype.registerOsapiServices = function() {
	gadgets.config.init({
		rpc: {
			parentRelayUrl: ''
		},
		views: gadgets.config.views,
		'osapi.services': {
			'http://%host%/__api_endpoint/os/1.0/rpc': ['people.get', 'people.getViewer',
				'people.getViewerFriends', 'people.getOwner', 'people.getOwnerFriends']
		}
	});
};
