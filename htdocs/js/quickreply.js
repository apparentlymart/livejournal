QuickReply = {
	lastDiv: 'qrdiv',
	
	reply: function(dtid, pid, newsubject)
	{
		var targetname = 'ljqrt' + dtid,
			qr_ptid = $('parenttalkid'),
			qr_rto = $('replyto'),
			qr_dtid = $('dtid'),
			qr_div = $('qrdiv'),
			cur_div = $(targetname),
			qr_form_div = $('qrformdiv'),
			qr_form = $('qrform'),
			subject = $('subject');
		
		// Is this a dumb browser?
		if (!qr_ptid || !qr_rto || !qr_dtid || !qr_div || !cur_div || !qr_form || !qr_form_div || !subject) {
			return true;
		}
		
		qr_ptid.value = pid;
		qr_dtid.value = dtid;
		qr_rto.value = pid;
		
		if (QuickReply.lastDiv == 'qrdiv') {
			qr_div.style.display = 'inline';
			// Only one swap
			cur_div.parentNode.insertBefore(qr_div, cur_div);
		} else if (QuickReply.lastDiv != dtid) {
			cur_div.parentNode.insertBefore(qr_div, cur_div);
		}
		
		QuickReply.lastDiv = targetname;
		
		if (!subject.value || subject.value == subject.defaultValue || subject.value.substr(0, 4) == 'Re: ') {
			subject.value = newsubject;
			subject.defaultValue = newsubject;
		}
		
		qr_form_div.className = cur_div.className || '';
		
		// have to set a timeout because most browsers won't let you focus
		// on an element that's still in the process of being created.
		// so lame.
		window.setTimeout(function(){ qr_form.body.focus() }, 100);
		
		return false;
	},
	
	more: function()
	{
		var qr_form = $('qrform'),
			basepath = $('basepath'),
			dtid = $('dtid'),
			pidform = $('parenttalkid');
		
		// do not do the default form action (post comment) if something is broke
		if (!qr_form || !basepath || !dtid || !pidform) {
			return false;
		}
		
		if(dtid.value > 0 && pidform.value > 0) {
			//a reply to a comment
			qr_form.action = basepath.value + "replyto=" + dtid.value;
		} else {
			qr_form.action = basepath.value + "mode=reply";
		}
		
		// we changed the form action so submit ourselves
		// and don't use the default form action
		qr_form.submit();
		return false;
	},
	
	submit: function()
	{
		var submitmore = $('submitmoreopts'),
			submit = $('submitpost');
		
		if (!submitmore || !submit) {
			return false;
		}
		
		submit.disabled = true;
		submitmore.disabled = true;
		
		// New top-level comments
		var dtid = $('dtid');
		if (!Number(dtid.value)) {
			dtid.value =+ 0;
		}
		
		var qr_form = $('qrform');
		qr_form.action = Site.siteroot + '/talkpost_do.bml';
		qr_form.submit();
		
		// don't do default form action
		return false;
	},
	
	check: function()
	{
		var qr_form = $('qrform');
		if (!qr_form) return true;
		var len = qr_form.body.value.length;
		if (len > 4300) {
			alert('Sorry, but your comment of ' + len + ' characters exceeds the maximum character length of 4300. Please try shortening it and then post again.');
			return false;
		}
		return true;
	},
	
	// Maintain entry through browser navigations.
	save: function()
	{
		var qr_form = $('qrform');
		if (!qr_form) {
			return false;
		}
		var do_spellcheck = $('do_spellcheck'),
			qr_upic = $('prop_picture_keyword');
		
		$('saved_body').value = qr_form.body.value;
		$('saved_subject').value = $('subject').value;
		$('saved_dtid').value = $('dtid').value;
		$('saved_ptid').value = $('parenttalkid').value;
		
		if (do_spellcheck) {
			$('saved_spell').value = do_spellcheck.checked;
		}
		if (qr_upic) { // if it was in the form
			$('saved_upic').value = qr_upic.selectedIndex;
		}
		
		return false;
	},
	
	// Restore saved_entry text across platforms.
	restore: function()
	{
		setTimeout(function(){
			var saved_body = $('saved_body'),
				dtid = $('saved_dtid'),
				subject = $('saved_subject'),
				subject_str = '',
				qr_form = $('qrform');
			if (!saved_body || saved_body.value == '' || !qr_form || !dtid) {
				return;
			}
			
			if (subject) {
				subject_str = subject.value;
			}
			
			QuickReply.reply(dtid.value, parseInt($('saved_ptid').value, 10), subject_str);
			
			qr_form.body.value = saved_body.value;
			
			// if it was in the form
			var upic = $('prop_picture_keyword');
			if (upic) {
				upic.selectedIndex = $('saved_upic').value;
			}
			
			var spellcheck = $('do_spellcheck');
			if (spellcheck) {
				spellcheck.checked = $('saved_spell').value == 'true';
			}
		}, 100);
	},
	
	userpicSelect: function()
	{
		var ups = new UserpicSelect();
		ups.init();
		ups.setPicSelectedCallback(function(picid, keywords)
		{
			var kws_dropdown = $('prop_picture_keyword');
			
			if (kws_dropdown) {
				var items = kws_dropdown.options;
				
				// select the keyword in the dropdown
				keywords.forEach(function(kw)
				{
					for (var i = 0; i < items.length; i++) {
						var item = items[i];
						if (item.value == kw) {
							kws_dropdown.selectedIndex = i;
							return;
						}
					}
				});
			}
		});
		ups.show();
	}
}

jQuery(QuickReply.restore);
DOM.addEventListener(window, 'unload', QuickReply.save);
