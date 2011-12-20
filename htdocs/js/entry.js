var layout_mode = "thin";
var sc_old_border_style;
var shift_init = "true";

if (! ("$" in window)) {
	$ = function(id) {
		if (document.getElementById) {
			return document.getElementById(id);
		}
		return null;
	};
}

function initEntryDate() {
	jQuery('#entrydate').entryDatePicker({
		//flag is set to true for new posts
		updateDate: !!window.updatePostTime,
		customTimeFlag: jQuery('#journal_time_edited')
	});
}

function revertdate() {
	jQuery('#entrydate').entryDatePicker('reset');
}

function setPostingPermissions(journal) {
	if (!('remote_permissions' in Site) || !Site.remote_permissions[journal]) {
		return;
	}

	var modifyDate = jQuery('#modifydate'), stickyCheckbox = jQuery('#sticky_type'), doNotAddType = jQuery('#entryform-do_not_add-wrapper'), stickyLabel = jQuery('#sticky_type_label'), stickyWrapper = jQuery('#entryform-sticky-wrapper'), currentDateEdit = jQuery('#currentdate-edit');

	doNotAddType[Site.currentJournal == journal ? 'show' : 'hide']();

	journal = Site.remote_permissions[journal];

	if (!journal.can_post_delayed) {
		if (modifyDate.is(':visible')) {
			revertdate();
		}
		currentDateEdit.hide();
	} else {
		currentDateEdit.show();
	}

	if (!journal.can_create_sticky) {
		stickyWrapper.hide();
		stickyCheckbox.prop('disabled', true);
	} else {
		stickyCheckbox.prop('disabled', false);
		stickyLabel.html(journal.is_replace_sticky ? Site.ml_text['entryform.sticky_replace.edit'] : Site.ml_text['entryform.sticky.edit']);
		stickyWrapper.css('display', '');
	}
}

function showEntryTabs() {
	if (CKEDITOR && CKEDITOR.env.isCompatible) {
		document.getElementById('entry-tabs').style.visibility = 'visible';
	} else {
		document.getElementById('htmltools').style.display = 'block';
	}
}

function changeSubmit(prefix, defaultjournal, defPrefix) {
	var usejournal = document.getElementById('usejournal'), formsubmit = document.getElementById('formsubmit'), newvalue, commname;

	if (!defaultjournal) {
		newvalue = prefix;
	} else if (!usejournal || usejournal.value == '') {
		newvalue = prefix + ' ' + defaultjournal;
		commname = defaultjournal;
	} else {
		if (usejournal.value === '[none]') {
			newvalue = defPrefix;
		} else {
			newvalue = prefix + ' ' + usejournal.value;
		}
		commname = usejournal.value;
	}
	formsubmit.disabled = ( /\[none\]/.test(commname) || /^ext_/.test(commname) );
	formsubmit.value = newvalue;
}

function new_post_load(dotime) {
	if (dotime) {
		window.updatePostTime = true;
	}

	var remotelogin = $('remotelogin');
	if (! remotelogin) {
		return;
	}
	var remotelogin_content = $('remotelogin_content');
	if (! remotelogin_content) {
		return;
	}
	remotelogin_content.onclick = altlogin;
	f = document.updateForm;
	if (! f) {
		return false;
	}

	var userbox = f.user;
	if (! userbox) {
		return false;
	}
	if (! Site.has_remote && userbox.value) {
		altlogin();
	}

	return false;
}

function updateRepostButtons(stateIndex) {
	var boxes = ['facebook', 'twitter'], input, label, parentNode, parentDisableClass = 'b-repost-item-disabled', linkDisclass = 'b-repost-item-dis';

	for (var i in boxes) {
		input = $('repost_' + boxes[i]);
		if (!input) {
			continue;
		}

		parentNode = input.parentNode;
		label = parentNode.getElementsByTagName('label')[0];

		if (stateIndex > 0 || parentNode.className.indexOf(parentDisableClass) != -1) {
			input.setAttribute('disabled', 'disabled');
			label.className = "repost_disabled";
			input.checked = false;
			if (parentNode.className.indexOf(linkDisclass) == -1) {
				parentNode.className += " " + linkDisclass;
			}
		} else {
			input.removeAttribute('disabled');
			label.className = "repost_" + boxes[i];
			parentNode.className = parentNode.className.replace(" " + linkDisclass, "");
		}
	}

}

function customboxes(e) {
	if (! e) {
		e = window.event;
	}
	if (! document.getElementById) {
		return false;
	}

	var f = document.updateForm;
	if (! f) {
		return false;
	}

	var security = $('security');

	var custom_boxes = $('custom_boxes');
	if (! custom_boxes) {
		return false;
	}

	updateRepostButtons(security.selectedIndex);

	if (security.selectedIndex != 3) {
		custom_boxes.style.display = 'none';
		return false;
	}

	var altlogin_username = $('altlogin_username');
	if (altlogin_username != undefined && (altlogin_username.style.display == 'table-row' || altlogin_username.style.display == 'block')) {
		security.selectedIndex = 0;
		custom_boxes.style.display = 'none';
		alert("Custom security is only available when posting as the logged in user.");
	} else {
		custom_boxes.style.display = 'block';
	}

	if (e) {
		e.cancelBubble = true;
		if (e.stopPropagation) {
			e.stopPropagation();
		}
	}
	return false;
}

function setCopyrightUpdate() {
	if ($('prop_copyright') && Site.default_copyright == "P") {
		$('prop_copyright').checked = 1;
	}
}

function detectLocation() {

	function myFunctionForLoadDistr(url) {
		//alert('Magic Scanner is not installed, download it at '+url);
		wi2Geo.response = true;
	}

	var wi2Geo = {};
	var gGears = {};

	wi2Geo.response = false;
	gGears.response = false;

	function updateWi2GeoPosition(q) {
		if (q) {
			wi2Geo.country = q.city.country;
			wi2Geo.city = q.city.name;
			wi2Geo.type = q.type;
			if (wi2Geo.type != 'IP') {
				wi2Geo.street = q.building.street;
				wi2Geo.building = q.building.address;
				wi2Geo.metro = q.metro.name;
			}
			wi2Geo.lat = q.lat;
			wi2Geo.lng = q.lng;
		}
		wi2Geo.response = true;
	}

	function updateGearsPosition(p) {
		if (p) {
			gGears.country = (!p.gearsAddress.country.match(/\?\?/gi) ? (p.gearsAddress.country) : (""));
			gGears.city = (!p.gearsAddress.city.match(/\?\?/gi) ? (p.gearsAddress.city) : (""));
			if (gGears.country == 'USA') {
				gGears.region = p.gearsAddress.region;
			}
			gGears.lat = p.coords.latitude;
			gGears.lng = p.coords.longitude;
			gGears.type = (p.accuracy < 1000 && p.accuracy > 0) ? ("nonIP") : ("IP");
			if (gGears.type != 'IP' && !p.gearsAddress.street.match(/\?\?/gi)) {
				gGears.street = p.gearsAddress.street;
				gGears.building = p.gearsAddress.streetNumber;
			}

		}
		gGears.response = true;
		wi2Geo.response = true;
	}

	try {
		var geo = google.gears.factory.create('beta.geolocation');
		geo.getCurrentPosition(updateGearsPosition, handleError, {enableHighAccuracy: true, gearsRequestAddress: true});
	} catch(e) {
		gGears.response = true;
		try {
			var myWi2GeoScanner = new Wi2GeoScanner('AQIAAKxzJUlHmzaMvzei5+vo3XLHJIdR', myFunctionForLoadDistr);
			myWi2GeoScanner.scan(updateWi2GeoPosition);
			if (window.opera) {
				wi2Geo.response = true;
			}
		} catch(e) {
			wi2Geo.response = true;
		}

	}

	function handleError(positionError) {
		gGears.response = true;
	}

	var si = window.setInterval(function getLocation() {
		if (wi2Geo.response && gGears.response) {
			window.clearInterval(si);
			var fCountry = (gGears.country || wi2Geo.country) ? ((gGears.country || wi2Geo.country) + ", ") : ("");
			var fRegion = (gGears.region || wi2Geo.region) ? ((gGears.region || wi2Geo.region) + ", ") : ("");
			var fCity = (gGears.city || wi2Geo.city) ? ((gGears.city || wi2Geo.city) + ", ") : ("");
			if (fRegion == fCity) {
				fRegion = "";
			}
			var fStreet = (gGears.street || wi2Geo.street) ? ((gGears.street || wi2Geo.street) + ", ") : ("");
			if (fStreet == "") {
				fCity = fCity.replace(/,/, "");
			}
			var fBuilding = gGears.building || wi2Geo.building || "";
			var fMetro = (wi2Geo.metro) || "";
			var fLat = (gGears.lat || wi2Geo.lat) ? ((gGears.lat || wi2Geo.lat) + ", ") : ("");
			var fLng = gGears.lng || wi2Geo.lng || "";
			if (!fCountry || !fCity || !fLat || !fLng) {
				HTTPReq.getJSON({url:'/tools/endpoints/geo_location.bml',
					onData:function(data) {
						if (data.data) {
							fCountry = (data.data.country_rus_name) ? (data.data.country_rus_name + ", ") : (data.data.country_name + ", ");
							fCity = data.data.city_rus_name || data.data.city_name;
							if (data.data.country_short == 'US') {
								fRegion = data.data.region_name + ", ";
							}
							fLat = data.data.latitude + ", ";
							fLng = data.data.longitude;
							$('prop_current_location').value = fCountry + fRegion + fCity;
						} else {
							$('prop_current_location').value = "Can't Detect";
							window.setTimeout(function() {
								$('prop_current_location').value = " "
							}, 3000);
						}
					},
					onError:LiveJournal.ajaxError
				});
			} else {
				$('prop_current_location').value = fCountry + fRegion + fCity + fStreet + fBuilding;
			}

		} else {
			$('prop_current_location').value = 'detecting...';
		}
	}, 100);

}

function setCopyrightEdit() {
	if ($('security') && $('prop_copyright')) {
		var copyright_flag = $('prop_copyright').checked;
		if ($('security').value != 'public') {
			$('prop_copyright').checked = false;
			$('prop_copyright').disabled = true;
		}
		$('security').onchange = function() {
			copyright(copyright_flag);
			customboxes();
		};
		$('prop_copyright').onchange = function() {
			copyright_flag = $('prop_copyright').checked;
		}
	}
}

function copyright(copyright_flag) {
	if ($('security') && $('prop_copyright')) {
		if ($('security').value != "public") {
			$('prop_copyright').checked = 0;
			$('prop_copyright').disabled = true;
			$('defined_copyright').value = '0';
		} else {
			if (Site.default_copyright == "P") {
				$('prop_copyright').checked = 1;
			}
			$('prop_copyright').disabled = false;
			$('prop_copyright').checked = copyright_flag;

			$('defined_copyright').value = '1';

		}

	}
}

function altlogin(e) {
	var agt = navigator.userAgent.toLowerCase();
	var is_ie = ((agt.indexOf("msie") != -1) && (agt.indexOf("opera") == -1));

	if (! e) {
		e = window.event;
	}
	if (! document.getElementById) {
		return false;
	}

	var altlogin_wrapper_login = $('altlogin_wrapper_login'), altlogin_wrapper_password = $('altlogin_wrapper_password');
	if (!altlogin_wrapper_login || !altlogin_wrapper_password) {
		return false;
	}
	altlogin_wrapper_login.style.display = '';
	altlogin_wrapper_password.style.display = '';

	var remotelogin = $('remotelogin');
	if (! remotelogin) {
		return false;
	}
	remotelogin.style.display = 'none';

	var usejournal_list = $('usejournal_list');
	if (usejournal_list) {
		usejournal_list.style.display = 'none';
	}

	var readonly = $('readonly');
	var userbox = f.user;
	if (!userbox.value && readonly) {
		readonly.style.display = 'none';
	}

	var userpic_list = $('userpic_select_wrapper');
	if (userpic_list) {
		userpic_list.style.display = 'none';
	}

	var userpic_preview = $('userpic_preview');
	if (userpic_preview) {
		userpic_preview.className = "";
		userpic_preview.innerHTML = "<img src='/img/userpic_loggedout.gif' alt='selected userpic' id='userpic_preview_image' class='userpic_loggedout' />";
	}

	var mood_preview = $('mood_preview');
	mood_preview.style.display = 'none';

	f = document.updateForm;
	if (! f) {
		return false;
	}
	f.action = 'update.bml?altlogin=1';

	var custom_boxes = $('custom_boxes');
	if (! custom_boxes) {
		return false;
	}
	custom_boxes.style.display = 'none';
	if (f.security) {
		f.security.options[3] = null;
	}

	f.security.selectedIndex = 0;

	if (e) {
		e.cancelBubble = true;
		if (e.stopPropagation) {
			e.stopPropagation();
		}
	}

	changeSubmit('Post to Journal', null, 'Post to Journal');

	if ($('usejournal_username')) {
		changeSecurityOptions($('usejournal_username').value);
	} else {
		changeSecurityOptions('');
	}

	return false;
}

function mood_preview() {
	if (! document.getElementById) {
		return false;
	}
	var mood_list = document.getElementById('prop_current_moodid'); // get select
	var moodid = mood_list[mood_list.selectedIndex].value; // get value of select
	var moodPreview;

	if (moodid == "") {
		if ($('mood_preview')) {
			moodPreview = $('mood_preview');
			moodPreview.innerHTML = '';
		}
		return false
	} else {
		var wrapper = $('entryform-mood-wrapper');
		if ($('mood_preview')) {
			moodPreview = $('mood_preview');
			moodPreview.innerHTML = '';
		} else {
			moodPreview = document.createElement('span');
			moodPreview.id = 'mood_preview';
			wrapper.appendChild(moodPreview);
		}
		var moodPreviewImage = document.createElement('img');
		moodPreviewImage.id = 'mood_image_preview';
		moodPreviewImage.src = moodpics[moodid];
		var moodPreviewText = document.createElement('span');
		moodPreviewText.id = 'mood_text_preview';
		var mood_custom_text = $('prop_current_mood').value;
		moodPreviewText.innerHTML = mood_custom_text == "" ? moods[moodid] : mood_custom_text;
		moodPreview.appendChild(moodPreviewImage);
		moodPreview.appendChild(moodPreviewText);
		if (moodPreview.style.display != 'none') {
			$('prop_current_music').className = $('prop_current_music').className + ' narrow';
			$('prop_current_location').className = $('prop_current_location').className + ' narrow';
		}
	}
}

function entryPreview(entryForm) {
	var action = entryForm.action;
	entryForm.onsubmit && entryForm.onsubmit(); // for rich editor, syn content
	entryForm.action = '/preview/entry.bml';
	entryForm.target = 'preview';
	window.open('', 'preview', 'width=760,height=600,resizable=yes,status=yes,toolbar=no,location=no,menubar=no,scrollbars=yes');
	entryForm.submit();
	entryForm.target = '_self';
	entryForm.action = action;
	return false;
}

function numberOfColumns(items) {
	if (items <= 6) {
		return 1
	} else if (items >= 7 && items <= 12) {
		return 2
	} else if (items >= 13 && items <= 18) {
		return 3
	} else {
		return 4
	}
}

function setColumns(number) {
	// we'll create all our variables here
	// if you want to change the names of any of the ids, change them here
	var listObj = document.getElementById('custom_boxes_list');                  // the actual ul
	var listWrapper = document.getElementById('custom_boxes');      // ul wrapper
	var listContainer = document.getElementById('list-container');  // container for dynamic content

	// create an array of all the LIs in the UL
	// or return if we have no custom groups
	if (listObj) {
		var theList = listObj.getElementsByTagName('LI');
	} else {
		return;
	}

	if (!listContainer) {	 // if div#list-container doesn't exist create it
		var listContainer = document.createElement('div');
		listContainer.setAttribute('id', 'list-container');
		listWrapper.appendChild(listContainer);
	} else {								// if it does exist, clear out any content
		listContainer.innerHTML = '';
	}

	// create and populate content arrays based on ul#list
	var content = new Array();
	var contentClass = new Array();
	var contentId = new Array();
	for (i = 0; i < theList.length; i++) {
		content[i] = theList[i].innerHTML;
		contentClass[i] = theList[i].className;
		contentId[i] = theList[i].id;
	}

	// hide original list
	listObj.style.display = 'none';

	// determine number of columns
	if (number) {	 // if it's passed as an argument
		var columns = number;
	} else {				// or use the numberOfColumns function to set it
		var columns = numberOfColumns(content.length);
	}

	// divide number of items by columns and round up to get the number of items per column
	var perColumn = Math.ceil(content.length / columns);

	// set the class of list-wrapper to reflect the number of columns
	if ((theList.length / perColumn) <= (columns - 1)) {
		// If the number of items divided by the calculated items per column is less than
		// the number of columns minus one, the number of columns will be adjusted down by one.
		// In other words, if you have 9 items and try to break them into 4 columns, the last
		// column would be empty, so I've made the adjustment automatic.
		columns = columns - 1;
	}
	listWrapper.className = 'columns' + columns;

	for (j = 0; j < columns; j++) { // insert columns into list-container
		if ((perColumn * j) >= theList.length) {
			return false;
		}

		var columnCounter = j + 1; // add 1 to give logical ids to ULs
		var ulist = document.createElement('ul');
		// ulist.setAttribute('class','column');
		// ulist.setAttribute('id','column-' + columnCounter);
		listContainer.appendChild(ulist);
		var start = perColumn * j;      // set where the for loop will start
		var end = perColumn * (j + 1);    // set where the for loop will end
		for (k = start; k < end; k++) {
			if (content[k]) {
				var listitem = document.createElement('li');
				listitem.setAttribute('class', contentClass[k]);
				listitem.setAttribute('id', contentId[k]);
				listitem.innerHTML = content[k];
				ulist.appendChild(listitem);
			}
		}
	}
	listWrapper.removeChild(listObj);
}

function tagAutocomplete(node, tags) {
	var searched;

	jQuery(node).autocomplete({
		minLength: 1,
		source: function(request, response) {
			var val = this.element.context.value, range = DOM.getSelectedRange(this.element.context);

			if (!val || range.start != range.end) {
				response([]);
				return;
			}

			// search one tag
			searched = val.match(new RegExp('(^.{0,' + (range.start - 1) + '},|^)([^,]*),?(.*)'));
			var tag = searched[2].replace(/^ +/, '');
			// delegate back to autocomplete, but extract term
			if (!tag) {
				response([]);
				return;
			}
			var resp_ary = [], i = -1;
			while (tags[++i]) {
				if (tags[i].indexOf(tag) === 0) {
					resp_ary.push(tags[i]);
					if (resp_ary.length === 10) {
						break;
					}
				}
			}

			response(resp_ary);
		},
		focus: function() {
			// prevent value inserted on focus
			return false;
		},
		select: function(e, ui) {
			ui.item.value += ',';

			if (searched[1].length) { // no start
				ui.item.value = ' ' + ui.item.value;
			}
			var new_range = searched[1].length + ui.item.value.length;
			if (!searched[3].length) { // empy in end
				ui.item.value += ' ';
				new_range++;
			} else { // set range before ", ..."
				new_range--;
			}

			this.value = searched[1] + ui.item.value + searched[3];
			DOM.setSelectedRange(this, new_range, new_range);

			e.preventDefault();
		},

		open: function() {
			var widget = jQuery(this).autocomplete('widget');
			// fix left pos in FF 3.6
			if (jQuery.browser.mozilla) {
				var offset = widget.offset();
				offset.left++;

				widget.offset(offset);
				widget.width(widget.width() + 3);
			} else {
				widget.width(widget.width() + 4);
			}
		}
	});
}

function getUserTags(user) {
	user = user || Site.currentJournal;

	jQuery('#prop_taglist').autocomplete('destroy');

	if (journalTags[user]) {
		tagAutocomplete($('prop_taglist'), journalTags[user]);
	} else {
		jQuery.getJSON('/tools/endpoints/gettags.bml?user=' + user, function(data) {
			if (data.tags) {
				tagAutocomplete($('prop_taglist'), data.tags);
			}
		});
	}
}

function selectTags(node) {
	var widget = new LJWidgetIPPU();

	widget.onRefresh = function() {
		IPPUSelectTags.widget = widget;
		IPPUSelectTags.init();
	};

	widget.init({
		title: node.firstChild.nodeValue,
		height: 329,
		width: jQuery(window).width() / 2,
		widgetClass: 'IPPU::SelectTags'
	}, {
		user: jQuery(document.forms.updateForm.usejournal).val()
	});
	widget.ippu.addClass('ippu-select-tags');
	widget.ippu.setClickToClose(false);

	return false;
}

IPPUSelectTags = {
	init: function(ippu_node) {
		$('selecttags-all').value = $('prop_taglist').value.split(/ *, */).join(', ');

		this.checkboxes = jQuery('div.b-selecttags-tags input:checkbox', ippu_node);

		jQuery('#selecttags-all').input(this.input).input();
	},

	change: function(node) {
		var inp = $('selecttags-all'), ary = inp.value.replace(/ */, '') ? inp.value.split(/ *, */) : [], i = -1;

		ary = jQuery.map(ary, function (val, idx) {
			return (val.length > 0) ? val : null
		});
		if (node.checked) {
			ary.push(node.value)
		} else {
			while (ary[++i]) {
				if (ary[i] == node.value) {
					ary.splice(i, 1);
					break;
				}
			}
		}

		inp.value = ary.join(', ');
	},

	input: function() {
		var ary = $('selecttags-all').value.split(/ *, */), checkboxes = IPPUSelectTags.checkboxes;
		ary = jQuery.map(ary, function (val, idx) {
			return (val.length > 0) ? val : null
		});
		checkboxes.attr('checked', false);
		while (ary.length) {
			checkboxes.filter('[value=' + ary.pop() + ']').attr('checked', true);
		}
	},

	save_click: function() {
		$('prop_taglist').value = $('selecttags-all').value.split(/ *, */).join(', ');
		this.widget.close();
	},

	reset_click: function() {
		$('selecttags-all').value = '';
		IPPUSelectTags.checkboxes.attr('checked', false);
	}
};

function _changeOptionState(option, enable) {
	if (option) {
		if (enable) {
			option.disabled = false;
			option.style.color = "";
		} else {
			option.disabled = true;
			option.style.color = "#999";
		}
	}
}

function changeSecurityOptions(user) {
	user = user || Site.currentJournal;

	HTTPReq.getJSON({
		url: "/tools/endpoints/getsecurityoptions.bml?user=" + user,
		method: "GET",
		onData: function (data) {
			if ($('security')) {
				// first empty out whatever is in the drop-down
				var prev_security = $('security').selectedIndex;
				for (i = 0; i < $('security').options.length; i++) {
					$('security').options[i] = null;
				}

				// if the user is known
				if (data.ret) {
					// give the appropriate security options for the account type
					if (data.ret['is_comm']) {
						$('security').options[0] = new Option(UpdateFormStrings.public, 'public');
						$('security').options[1] = new Option(UpdateFormStrings.friends_comm, 'friends');
						if (prev_security > $('security').options.length - 1) {
							prev_security = $('security').options.length - 1;
						}
					} else {
						$('security').options[0] = new Option(UpdateFormStrings.public, 'public');
						$('security').options[1] = new Option(UpdateFormStrings.friends, 'friends');
						$('security').options[2] = new Option(UpdateFormStrings.private, 'private');
						if (data.ret['friend_groups_exist']) {
							$('security').options[3] = new Option(UpdateFormStrings.custom, 'custom');
						}
					}

					// select the minsecurity value and disable the values with lesser security
					if (data.ret['minsecurity'] == "friends") {
						$('security').selectedIndex = Math.max(1, prev_security);
						_changeOptionState($('security').options[0], false);
					} else if (data.ret['minsecurity'] == "private") {
						$('security').selectedIndex = Math.max(2, prev_security);
						_changeOptionState($('security').options[0], false);
						_changeOptionState($('security').options[1], false);
						_changeOptionState($('security').options[3], false);
					} else {
						$('security').selectedIndex = Math.max(0, prev_security);
						_changeOptionState($('security').options[0], true);
						_changeOptionState($('security').options[1], true);
						_changeOptionState($('security').options[2], true);
						_changeOptionState($('security').options[3], true);
					}

					// remove custom friends groups boxes if needed
					customboxes();

					// if the user is not known
				} else {
					// personal journal, but no custom option, and no minsecurity
					$('security').options[0] = new Option(UpdateFormStrings.public, 'public');
					$('security').options[1] = new Option(UpdateFormStrings.friends, 'friends');
					$('security').options[2] = new Option(UpdateFormStrings.private, 'private');
					$('security').selectedIndex = 0;
					_changeOptionState($('security').options[0], true);
					_changeOptionState($('security').options[1], true);
					_changeOptionState($('security').options[2], true);
				}
			}
		},
		onError: function (msg) {
		}
	});
}

///////////////////// Insert Object code

var InOb = new Object;

InOb.fail = function (msg) {
	alert("FAIL: " + msg);
	return false;
};

// image upload stuff
InOb.onUpload = function (surl, furl, swidth, sheight) {

	var html = "\n<a href=\"" + furl + "\"><img src=\"" + surl + "\" width=\"" + swidth + "\" height=\"" + sheight + "\" border='0'/></a>";

	if (window.switchedRteOn) {
		var dialog = CKEDITOR.dialog.getCurrent();

		dialog.setValueOf('info', 'txtUrl', surl);
		dialog.setValueOf('info', 'txtWidth', swidth);
		dialog.setValueOf('info', 'txtHeight', sheight);
		dialog.setValueOf('Link', 'txtUrl', furl);
		dialog.selectPage('info');
		InOb.showSelectorPage();
	} else {
		var ta = $("updateForm");
		if (!ta) {
			return InOb.fail("no updateform");
		}
		ta = ta.event;

		var selection = DOM.getSelectedRange($('draft'));
		var value = ta.value;
		var start = value.substring(0, selection.start);
		var end = value.substring(selection.end);
		ta.value = start + "\n" + html + end;
	}
};

InOb.onInsURL = function (url, width, height) {
	var ta = $("updateForm");
	var fail = function (msg) {
		alert("FAIL: " + msg);
		return 0;
	};
	if (! ta) {
		return fail("no updateform");
	}
	var w = '';
	var h = '';
	if (width > 0) {
		w = " width='" + width + "'";
	}
	if (height > 0) {
		h = " height='" + height + "'";
	}
	ta = ta.event;

	var html = "<img src=\"" + url + "\"" + w + h + " />";

	if (window.switchedRteOn) {
		CKEDITOR.instances.draft.insertHtml(html);
	} else {
		var selection = DOM.getSelectedRange($('draft'));
		var value = ta.value;
		var start = value.substring(0, selection.start);
		var end = value.substring(selection.end);
		ta.value = start + "\n" + html + end;
	}
	return true;
};

var currentPopup;        // set when we make the iframe
var currentPopupWindow;  // set when the iframe registers with us and we setup its handlers
function onInsertObject(include) {
	InOb.onClosePopup();

	//var iframe = document.createElement("iframe");
	var container = document.createElement('div');
	container.id = 'updateinsobject';
	container.className = 'updateinsobject';
	container.style.overflow = 'hidden';
	container.style.border = '0';
	container.style.backgroundColor = '#fff';
	container.style.zIndex = 1000;
	container.style.position = 'fixed';

	var iframe = document.createElement('iframe');
	iframe.id = 'popupsIframe';
	iframe.style.border = 'none';
	iframe.frameBorder = 0;
	iframe.height = iframe.width = '100%';
	iframe.src = include;

	document.body.appendChild(container);
	container.appendChild(iframe);
	currentPopup = container;
	InOb.smallCenter();

	InOb.onresize = function() {
		return InOb.smallCenter();
	};

	jQuery(window).resize(InOb.resize);
}
// the select's onchange:
InOb.handleInsertSelect = function () {
	var objsel = $('insobjsel');
	if (! objsel) {
		return InOb.fail('can\'t get insert select');
	}

	var selected = objsel.selectedIndex;
	var include;

	objsel.selectedIndex = 0;

	if (selected == 0) {
		return true;
	} else if (selected == 1) {
		include = 'imgupload.bml';
	} else {
		alert('Unknown index selected');
		return false;
	}

	onInsertObject(include);

	return true;
};

InOb.handleInsertEmbed = function () {
	LJ_IPPU.textPrompt(top.CKLang.LJEmbedPromptTitle, top.CKLang.LJEmbedPrompt, function(content) {
		var selection = DOM.getSelectedRange($('draft'));
		var node = $('updateForm').event;
		var value = node.value;
		var start = value.substring(0, selection.start);
		var end = value.substring(selection.end);
		node.value = start + '<lj-embed>\n' + content + '\n</lj-embed>' + end;
	}, {
		width: '350px'
	});
};

InOb.handleInsertImageBeta = function () {
	var jSortable, jPhotoUploader = jQuery('#updateForm');

	jPhotoUploader.photouploader('option', 'type', 'upload').bind('htmlready',
		function (event) {
			var selection = DOM.getSelectedRange($('draft'));
			var node = $('draft');
			var value = node.value;
			var start = value.substring(0, selection.start);
			var end = value.substring(selection.end);
			node.value = start + event.htmlStrings.join('') + end;
		}).bind('endupload',
		function() {
			jSortable.sortable('enable').sortable('refresh');
		}).bind('uploading',
		function() {
			jSortable.sortable('disable');
		}).bind('removeitem',
		function () {
			jSortable.sortable('refresh');
		}).photouploader('show');

	jSortable = jQuery('.b-popup-pics-gallery-list');
	jSortable.sortable({
		axis: 'x',
		disabled: true,
		stop: function() {
			jPhotoUploader.photouploader('update');
		}
	});

	jSortable.disableSelection();

	return true;
};

InOb.handleInsertImage = function () {
	onInsertObject('/imgupload.bml');
	return true;
};

InOb.handleInsertVideo = function() {
	var videoUrl = prompt('Please enter a video URL:');
	var draft = $('draft');
	var video = "<lj-template name=\"video\">" + videoUrl + "</lj-template>";
	draft.value = draft.value + video;
};

InOb.resize = function() {
	InOb.onresize();
};

InOb.onClosePopup = function () {
	//close dialog even if it's the rte one
	//used when we insert image from scrapbook and should not interfere in other cases
	if (window.switchedRteOn) {
		var dialog = window.top.CKEDITOR.dialog.getCurrent();
		if (dialog) {
			dialog.hide();
		}
	}

	if (! currentPopup) {
		return;
	}
	document.body.removeChild(currentPopup);

	jQuery(window).unbind('resize', InOb.resize);
	currentPopup = null;
};

InOb.setupIframeHandlers = function (fromRte) {
	var ife = $("popupsIframe") || $('rteUpload');  //currentPopup;
	if (! ife) {
		return InOb.fail('handler without a popup?');
	}
	var ifw = ife.contentWindow;
	currentPopupWindow = ifw;
	if (! ifw) {
		return InOb.fail("no content window?");
	}

	var el;

	el = ifw.document.getElementById("fromurl");
	if (el) {
		el.onclick = function () {
			return InOb.selectRadio("fromurl");
		};
	}
	el = ifw.document.getElementById("fromurlentry");
	if (el) {
		el.onclick = function () {
			return InOb.selectRadio("fromurl");
		};
	}
	if (el) {
		el.onkeypress = function () {
			return InOb.clearError();
		};
	}
	el = ifw.document.getElementById("fromfile");
	if (el) {
		el.onclick = function () {
			return InOb.selectRadio("fromfile");
		};
	}
	el = ifw.document.getElementById("fromfileentry");
	if (el) {
		el.onclick = el.onchange = function () {
			return InOb.selectRadio("fromfile");
		};
	}
	el = ifw.document.getElementById("fromfb");
	if (el) {
		el.onclick = function () {
			return InOb.selectRadio("fromfb");
		};
	}
	el = ifw.document.getElementById("btnPrev");
	if (el) {
		el.onclick = InOb.onButtonPrevious;
	}

};

InOb.selectRadio = function (which) {
	// if(! currentPopup){
	// 	alert('no popup');
	// 	alert(window.parent.currentPopup);
	// 	return false;
	// }
	// if(! currentPopupWindow){
	// 	return InOb.fail('no popup window');
	// }

	var radio = currentPopupWindow.document.getElementById(which);
	if (! radio) {
		return InOb.fail('no radio button');
	}
	radio.checked = true;

	var fromurl = currentPopupWindow.document.getElementById('fromurlentry');
	var fromfile = currentPopupWindow.document.getElementById('fromfileentry');
	var submit = currentPopupWindow.document.getElementById('btnNext');
	if (! submit) {
		return InOb.fail('no submit button');
	}

	// clear stuff
	if (which != 'fromurl' && fromurl) {
		fromurl.value = '';
	}

	if (which != 'fromfile') {
		var filediv = currentPopupWindow.document.getElementById('filediv');
		filediv.innerHTML = filediv.innerHTML;
	}

	// focus and change next button
	if (which == "fromurl" && fromurl) {
		submit.value = 'Insert';
		fromurl.focus();
	}

	else if (which == "fromfile") {
		submit.value = 'Upload';
		fromfile.focus();
	}

	else if (which == "fromfb") {
		submit.value = "Next \u2192";  // &#x2192 is a right arrow
		// fromfile.focus();
	}

	return true;
};

// getElementById
InOb.popid = function (id) {
	var popdoc = currentPopupWindow.document;
	return popdoc.getElementById(id);
};

InOb.onSubmit = function () {
	var fileradio = InOb.popid('fromfile');
	var urlradio = InOb.popid('fromurl');
	var fbradio = InOb.popid('fromfb');

	var form = InOb.popid('insobjform');
	if (! form) {
		return InOb.fail('no form');
	}

	var div_err = InOb.popid('img_error');
	if (!div_err) {
		return InOb.fail('Unable to get error div');
	}

	var setEnc = function (vl) {
		form.encoding = vl;
		if (form.setAttribute) {
			form.setAttribute("enctype", vl);
		}
	};

	if (fileradio && fileradio.checked) {
		form.action = currentPopupWindow.fileaction;
		setEnc("multipart/form-data");
		return true;
	}

	if (urlradio && urlradio.checked) {
		var url = InOb.popid('fromurlentry');
		if (! url) {
			return InOb.fail('Unable to get url field');
		}

		if (url.value == '') {
			div_err.style.display = 'block';
			InOb.setError('You must specify the image\'s URL');
			return false;
		} else if (url.value.match(/html?$/i)) {
			div_err.style.display = 'block';
			InOb.setError('It looks like you are trying to insert a web page, not an image');
			return false;
		}

		setEnc("application/x-www-form-urlencoded");
		form.action = currentPopupWindow.urlaction;
		return true;
	}

	if (fbradio && fbradio.checked) {
		InOb.fotobilderStepOne();
		return false;
	}

	alert('unknown radio button checked');
	return false;
};

InOb.showSelectorPage = function () {
	var div_if = InOb.popid("img_iframe_holder");
	var div_fw = InOb.popid("img_fromwhere");
	div_fw.style.display = "block";
	div_fw.style.height = "100%";
	div_if.style.height = "100%";
	div_if.style.display = "none";

	InOb.setPreviousCb(null);
	InOb.setTitle('');
	InOb.showNext();

	if (!window.switchedRteOn) {
		setTimeout(function () {
			InOb.smallCenter();
			InOb.selectRadio("fromurl");
		}, 200);
	}
	var div_err = InOb.popid('img_error');
	if (div_err) {
		div_err.style.display = 'none';
	}
};

InOb.fotobilderStepOne = function () {
	//whole hack to make this work in both rte and non-rte dialogs
	if (!window.switchedRteOn) {
		InOb.fullCenter();
		InOb.onresize = function() {
			return InOb.fullCenter();
		};
	}
	var div_if = InOb.popid("img_iframe_holder");
	var div_fw = InOb.popid("img_fromwhere");

	div_fw.style.display = "none";
	div_if.style.display = "block";
	div_fw.style.height = "100%";
	div_if.style.height = "100%";
	var url = currentPopupWindow.fbroot + "/getgals";

	if (window.switchedRteOn) {
		url += 'rte';
		div_if.innerHTML = '<iframe id="fbstepframe" src="' + url + '" height="99%" width="99%" frameBorder="0" style="margin: 0 auto;"></iframe>';
	} else {
		div_if.innerHTML = "<iframe id='fbstepframe' src=\"" + url + "\" height=\"95%\" width='99%' frameBorder='0' style='margin: 0 auto;'></iframe>";
	}
	InOb.setPreviousCb(InOb.showSelectorPage);
};

InOb.photobucket = function (seedurl, pb_affsite_id) {
	InOb.tallCenter();
	InOb.onresize = function() {
		return InOb.tallCenter();
	};
	var div_if = InOb.popid("img_iframe_holder");
	var windims = DOM.getClientDimensions();
	DOM.setHeight(div_if, 450);
	var div_fw = InOb.popid("img_fromwhere");
	div_fw.style.display = "none";
	div_if.style.display = "block";

	var cb_url = "&url=" + escape(seedurl);

	div_if.innerHTML = '<iframe name="jwidget" id="jwidget" src="http://photobucket.com/svc/jwidget.php?width=360&height=400&largeThumb=true&pbaffsite=' + pb_affsite_id + '&bg=%23FFFFFF&border=false&bordercolor=%23000000' + cb_url + '&linkType=url&textcolor=%23000000&linkcolor=%230000FF&media=image&btntxt=Paste&dimensions=false&promo=false" bgcolor="transparent" width="99%" height="440" frameBorder="0" scrolling="no"></iframe>';
	InOb.setPreviousCb(InOb.showSelectorPage);
};

InOb.fullCenter = function () {
	var windims = DOM.getClientDimensions(), h2 = Math.floor((windims.y - 220) / 2), //half of real height, we do not want to round numbers again
		w2 = Math.floor((windims.x - 55) / 2)

	DOM.setHeight(currentPopup, h2 * 2);
	DOM.setWidth(currentPopup, w2 * 2);

	currentPopup.style.top = '50%';
	currentPopup.style.marginTop = '-' + h2 + 'px';

	currentPopup.style.left = '50%';
	currentPopup.style.marginLeft = '-' + w2 + 'px';

	//put iframe resize logic here from fotoBilderStepOne
	try {
		var div_if = InOb.popid("img_iframe_holder");
		if (!window.switchedRteOn) {
			var windims = DOM.getClientDimensions();
			DOM.setHeight(div_if, windims.y - 270);
			var h = windims.y - 350;
		} else {
			div_if.style.height = '99%';
		}
	} catch(e) {
	}
};

InOb.tallCenter = function () {
	DOM.setHeight(currentPopup, 500);
	DOM.setWidth(currentPopup, 420);

	currentPopup.style.top = '50%';
	currentPopup.style.marginTop = '-250px';

	currentPopup.style.left = '50%';
	currentPopup.style.marginLeft = '-210px';
};

InOb.smallCenter = function () {
	DOM.setHeight(currentPopup, 307);
	DOM.setWidth(currentPopup, 700);

	currentPopup.style.top = '50%';
	currentPopup.style.marginTop = '-150px';

	currentPopup.style.left = '50%';
	currentPopup.style.marginLeft = '-350px';
};

InOb.setPreviousCb = function (cb) {
	var btnPrev = InOb.popid("btnPrev");
	InOb.cbForBtnPrevious = cb;
	btnPrev.style.display = cb ? "block" : "none";
	btnPrev.value = btnPrev.value.replace('<--', '\u2190')
};

// all previous clicks come in here, then we route it to the registered previous handler
InOb.onButtonPrevious = function () {
	InOb.showNext();

	if (InOb.cbForBtnPrevious) {
		return InOb.cbForBtnPrevious();
	}

	// shouldn't get here, but let's ignore the event (which would do nothing anyway)
	return true;
};

InOb.setError = function (errstr) {
	var div_err = InOb.popid('img_error');
	if (! div_err) {
		return false;
	}

	div_err.innerHTML = errstr;
	return true;
};

InOb.clearError = function () {
	var div_err = InOb.popid('img_error');
	if (! div_err) {
		return false;
	}

	div_err.innerHTML = '';
	return true;
};

InOb.disableNext = function () {
	var next = currentPopupWindow.document.getElementById('btnNext');
	if (! next) {
		return InOb.fail('no next button');
	}

	next.disabled = true;

	return true;
};

InOb.enableNext = function () {
	var next = currentPopupWindow.document.getElementById('btnNext');
	if (! next) {
		return InOb.fail('no next button');
	}

	next.disabled = false;

	return true;
};

InOb.hideNext = function () {
	var next = currentPopupWindow.document.getElementById('btnNext');
	if (! next) {
		return InOb.fail('no next button');
	}

	DOM.addClassName(next, 'display_none');

	return true;
};

InOb.showNext = function () {
	var next = currentPopupWindow.document.getElementById('btnNext');
	if (! next) {
		return InOb.fail('no next button');
	}

	DOM.removeClassName(next, 'display_none');

	return true;
};

InOb.setTitle = function (title) {
	var wintitle = currentPopupWindow.document.getElementById('wintitle');
	wintitle.innerHTML = title;
};
