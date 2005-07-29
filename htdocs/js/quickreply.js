    var LJVAR;
    if (! LJVAR) LJVAR = new Object()

    var lastDiv;
    lastDiv = 'qrdiv';

    function regEvent (target, evt, func) {
      if (! target) return;
      if (target.attachEvent)
        target.attachEvent("on"+evt, func);
      if (target.addEventListener)
        target.addEventListener(evt, func, false);
    }

    function quickreply(dtid, pid, newsubject) {
        var ev = window.event;

        // Mac IE 5.x does not like dealing with
        // nextSibling since it does not support it
        if (xIE4Up && xMac) { return true; }

        // on IE, cancel the bubble of the event up to the page. other
        // browsers don't seem to bubble events up registered this way.
        if (ev) {
            if (ev.stopPropagation)
               ev.stopPropagation();
            if ("cancelBubble" in ev)
                ev.cancelBubble = true;
        }

        var targetname = "ljqrt" + dtid;

        var ptalkid = xGetElementById('parenttalkid');
        var rto = xGetElementById('replyto');
        var dtid_field = xGetElementById('dtid');
        var qr_div = xGetElementById('qrdiv');
        var cur_div = xGetElementById(targetname);
        var qr_form_div  = xGetElementById('qrformdiv');
        var qr_form = xGetElementById('qrform');

        // Is this a dumb browser (like opera)?
        if( !ptalkid || !rto || !dtid_field || !qr_div || !cur_div || !qr_form ||
            !qr_form_div) {
           return true;
        }

        ptalkid.value = pid;
        dtid_field.value = dtid;
        rto.value = pid;

        if (lastDiv == 'qrdiv') {
            if (! showQRdiv(qr_div)) {
               return true;
            }

            // Only one swap
            if (! swapnodes(qr_div, cur_div)) {
                return true;
            }
        } else if (lastDiv != dtid) {
            var last_div = xGetElementById(lastDiv);
            // Two swaps
            if ((last_div != cur_div) && ! (swapnodes(last_div, cur_div) && swapnodes(qr_div, last_div))) {
                return true;
            }
        }

        lastDiv = targetname;

        var subject = xGetElementById('subject');
        if (subject) {
          if(!subject.value) subject.value = newsubject;
        } else {
          return true;
        }

        if(cur_div.className) {
          qr_form_div.className = cur_div.className;
        } else {
          qr_form_div.className = "";
        }

        // So it does not follow the link
        return false;
    }

    function moreopts()
    {
        var qr_form = xGetElementById('qrform');
        var basepath = xGetElementById('basepath');
        var dtid = xGetElementById('dtid');
        var pidform = xGetElementById('parenttalkid');

        var replyto = Number(dtid.value);
        var pid = Number(pidform.value);

        if(replyto > 127 && pid > 0) {
          //not a reply to a comment
          qr_form.action = basepath.value + "replyto=" + replyto;
        } else {
          qr_form.action = basepath.value + "mode=reply";
        }
        return true;
    }

   function submitform()
   {
        var submit = xGetElementById('submitpost');
        submit.disabled = true;

        var submitmore = xGetElementById('submitmoreopts');
        submitmore.disabled = true;

        // New top-level comments
        var dtid = xGetElementById('dtid');
        if (!Number(dtid.value)) {
            dtid.value =+ 0;
        }

        var qr_form = xGetElementById('qrform');
        qr_form.submit();
   }

   function swapnodes (orig, to_swap) {
        var orig_pn = xParent(orig, true);
        var next_sibling = orig.nextSibling;
        var to_swap_pn = xParent(to_swap, true);
        if (! to_swap_pn) {
            return false;
        }

        to_swap_pn.replaceChild(orig, to_swap);
        orig_pn.insertBefore(to_swap, next_sibling);
        return true;
   }

   function checkLength() {
        var textbox = xGetElementById('body');
        if (!textbox) return true;
        if (textbox.value.length > 4300) {
             alert('Sorry, but your comment of ' + textbox.value.length + ' characters exceeds the maximum character length of 4300.  Please try shortening it and then post again.');
             return false;
        }
        return true;
   }

    // Maintain entry through browser navigations.
    function save_entry() {
        var qr_body = xGetElementById('body');
        if (!qr_body) return false;
        var qr_subject = xGetElementById('subject');
        var do_spellcheck = xGetElementById('do_spellcheck');
        var qr_dtid = xGetElementById('dtid');
        var qr_ptid = xGetElementById('parenttalkid');
        var qr_upic = xGetElementById('prop_picture_keyword');

        var qr_saved_body = xGetElementById('saved_body');
        var qr_saved_subject = xGetElementById('saved_subject');
        var saved_do_spellcheck = xGetElementById('saved_spell');
        var qr_saved_dtid = xGetElementById('saved_dtid');
        var qr_saved_ptid = xGetElementById('saved_ptid');
        var qr_saved_upic = xGetElementById('saved_upic');

        qr_saved_body.value = qr_body.value;
        qr_saved_subject.value = qr_subject.value;
        if(do_spellcheck) {
          saved_do_spellcheck.value = do_spellcheck.checked;
        }

        qr_saved_dtid.value = qr_dtid.value;
        qr_saved_ptid.value = qr_ptid.value;

        if (qr_upic) { // if it was in the form
            qr_saved_upic.value = qr_upic.selectedIndex;
        }

        return false;
    }

    // Restore saved_entry text across platforms.
    function restore_entry() {
        setTimeout(
            function () {

                var saved_body = xGetElementById('saved_body');
                if (!saved_body || saved_body.value == "") return false;

                var dtid = xGetElementById('saved_dtid');
                if (! dtid) return false;
                var ptid = xGetElementById('saved_ptid');
                ptid += 0;

                quickreply(dtid.value, ptid.value, saved_body.value);

                var body = xGetElementById('body');
                if (! body) return false;
                body.value = saved_body.value;

                // Some browsers require we explicitly set this after the div has moved
                // and is now no longer hidden
                var qr_saved_subject = xGetElementById('saved_subject');
                var qr_saved_spell = xGetElementById('saved_spell');
                var qr_saved_dtid = xGetElementById('saved_dtid');
                var qr_saved_ptid = xGetElementById('saved_ptid');
                var qr_saved_upic = xGetElementById('saved_upic');

                var subject = xGetElementById('subject');
                if (! subject) return false;
                subject.value = qr_saved_subject.value

                var prop_picture_keyword = xGetElementById('prop_picture_keyword');
                if (prop_picture_keyword) { // if it was in the form
                    prop_picture_keyword.selectedIndex = qr_saved_upic.value;
                }

                var spell_check = xGetElementById('do_spellcheck');
                if (! spell_check) return false;
                if (qr_saved_spell.value == 'true') {
                    spell_check.checked = true;
                } else {
                    spell_check.checked = false;
                }

            }, 100);
        return false;
    }

    function showQRdiv(qr_div) {
        if (! qr_div) {
            qr_div = xGetElementById('qr_div');
            if (! qr_div) {
                return false;
            }
        } else if (qr_div.style && xDef(qr_div.style.display)) {
            qr_div.style.display='inline';
            return true;
        } else {
            return false;
        }
    }

    //after the functions have been defined, register them
    regEvent(window, 'load', restore_entry);
    regEvent(window, 'unload', save_entry);
