
function initTagPage()
{
    // initial page load - setup page elements based on
    // what is selected in the option list.
    // (initial page load has nothing selected, of course,
    // but we need to check anyway for 'back' button stuff.)
    var list = document.getElementById("tags");
    if (list) tagselect(list);
}

function toggle_actions(enable, just_rename)
{
    var form = document.getElementById("tagform");
    if (! form) return;

    // names of form elements to disable/enable
    // on item selections
    var toggle_elements = new Array("rename", "rename_field", "delete", "show posts");

    for ( $i = 0; $i < toggle_elements.length; $i++ ) {
        var ele = form.elements[ toggle_elements[$i] ];
        if (just_rename && $i > 1) continue;  // FIXME: remove after merge is decided
        ele.disabled = ! enable;
    }
}

function tagselect(list)
{
    if (! list) return;

    var selected_num = 0;        // counter
    var selected = new Array();  // tagnames, for display

    var selected_id;             // tag id if only one selected
    var id_re = /^\d+/;

    for ( $i = 0; $i < list.options.length; $i++ ) {
        if (list.options[$i].selected) {
            var val = list.options[$i].value.replace( /&/g, "&amp;" );
            selected[selected_num] = val.substring( val.indexOf('_')+1 );
            selected_num++;
            selected_id = val.match(id_re);
        }
    }

    var form = document.getElementById("tagform");
    if (! form) return;

    var tagfield   = document.getElementById("selected_tags");
    var tagprops   = document.getElementById("tag_props");
    var rename_btn = form.elements[ "rename" ];
    if (! tagfield || ! tagprops || ! rename_btn) return;

    // reset any 'red' fields
    reset_field( form.elements[ "rename_field" ]);
    reset_field( form.elements[ "add_field" ]);

    // no selections
    if (! selected_num) {
        toggle_actions(false);
        rename_btn.value = "Rename";
        show_props(tagprops);
    } else {
        toggle_actions(true);
        tagfield.innerHTML = selected.join(", ");

        // exactly one selection
        if (selected_num == 1) {
            rename_btn.value = "Rename";
            show_props(tagprops, selected_id);
        }

        // multiple items selected
        else {
            // FIXME: enable after merging is decided
            //rename_btn.value = "Merge";
            toggle_actions(false, 1); // FIXME: delete after merging is decided
            show_props(tagprops);
        }
    }

}

// just check for non-space characters or 'bad phrase',
// change css on problems.
function validate_input(btn, field_name, badtext)
{
    var form = document.getElementById("tagform");
    if (! form) return true;  // let submit happen
    var field = form.elements[ field_name ];
    if (! field) return true;

    var re = /\S/;
    if (! field.value.match(re) || field.value.indexOf(badtext) != -1) {
        field.className = 'tagfield_error';
        return false;
    }

    return true;
}

function reset_field(field, resettext)
{
    if ( !field ) return;
    field.className = 'tagfield';
    if (resettext && field.value.indexOf(resettext) != -1) field.value = '';
}

// update tag properties - display with 
// security counts.  right now, we have a 
// JS array with everything in tags.bml.
// eventually, this needs to be some xml-rpc goodness,
// with JS caching on the results of rpc calls.
function show_props(div, id)
{
    var tag = tags[id];
    var out;

    if (! tag) tag = [ 'n/a', 'n/a', '-', '-', '-', '-', '-' ];

    var secimg = '&nbsp; <img align="middle" src="/img/';
    if (tag[1] == "public") {
        secimg = secimg + "userinfo.gif";
    }
    else if (tag[1] == "private") {
        secimg = secimg + "icon_private.gif";
    }
    else if (tag[1] == "friends") {
        secimg = secimg + "icon_protected.gif";
    } 
    else {
        secimg = secimg + "icon_protected.gif";
    }
    secimg = secimg + '" />';
    if (tag[1] == "n/a") secimg = "";

    out = "<table class='proptbl' cellspacing='0'>";
    out = out + "<tr><td class='h' colspan='2'>counts and security</td></tr>";
    out = out + "<tr><td class='t'>public</td><td class='c'>" + tag[2] + "</td></tr>";
    out = out + "<tr><td class='t'>private</td><td class='c'>" + tag[3] + "</td></tr>";
    out = out + "<tr><td class='t'>friends</td><td class='c'>" + tag[4] + "</td></tr>";
    out = out + "<tr><td class='t'>custom groups</td><td class='c'>" + tag[5] + "</td></tr>";
    out = out + "<tr><td class='r'>total</td><td class='rv'>" + tag[6] + "</td></tr>";
    out = out + "<tr><td class='r' style='height: 16px'>security</td><td class='rv' align='middle'>" + tag[1] + secimg + "</td></tr>";
    out = out + "</table>";

    div.innerHTML = out;
    return;
}

// for edittags.bml
EditTag =
{
	// cache options value
	list_hash: {},
	
	init: function()
	{
		var tagfield = $('tagfield'),
			list = $('edit_tagform').tags,
			$list = jQuery(list),
			i = list.options.length;
		
		$list.val(tagfield.value.split(/,\s*/));
		
		
		while(i--) {
			this.list_hash[list.options[i].value] = list.options[i];
		}
		
		var timeout;
		jQuery(tagfield).bind('input keyup paste', function()
		{
			clearTimeout(timeout);
			timeout = setTimeout(function()
			{
				$list.val(tagfield.value.split(/,\s*/));
			}, 50);
		});
		
		$list.bind(jQuery.browser.msie ?
			'change' : // IE support metaKey in onchange
			'click keyup', EditTag.select);
	},
	
	select: function(e)
	{
		var $list = jQuery(this);
			selected = $list.val(), // tagnames, for display
			cache_val = selected && selected.join(',');
		
		// no need update input
		if (cache_val == EditTag.last_val) {
			return;
		}
		
		var cache_list = EditTag.list_hash,
			tagfield = $('tagfield'),
			cur_tags = tagfield.value.split(/,\s*/),
			i, tag;

		var index,
			top = this.scrollTop; // jump to last element in FF 3.6
		if (e.type === 'keyup') {
			
			for (i = -1; selected[++i];) {
				cache_list[selected[i]].selected = false;
			}
			selected = [];
			for (i = -1; cur_tags[++i];) {
				cache_list[cur_tags[i]].selected = true;
			}
			
			this.scrollTop = top;
		} else if (e.metaKey) {
			i = cur_tags.length;
			while (i--) {
				tag = cur_tags[i];
				if (cache_list[tag]) {
					if (!cache_list[tag].selected) {
						cur_tags.splice(i, 1);
					}
				}
			}
		} else {
			
			i = cur_tags.length;
			while (i--) {
				tag = cur_tags[i];
				// no items selected or empty
				if ( (!selected && cache_list[tag]) || tag == '') {
					cur_tags.splice(i, 1);
				} else if (selected && ~(index = selected.indexOf(tag)) ) {
					cur_tags.splice(i, 1);
					cache_list[
						selected.splice(index, 1)[0]
					].selected = false;
				} else if (cache_list[tag]) {
					cache_list[tag].selected = true;
				}
			}
			this.scrollTop = top;
		}
		
		// unique merge
		if (selected) {
			i = -1;
			while (selected[++i]) {
				if (!~cur_tags.indexOf(selected[i])) {
					cur_tags.push(selected[i]);
				}
			}
		}
		tagfield.value = cur_tags.join(', ');
		
		selected = $list.val();
		EditTag.last_val = selected && selected.join(',');
	}
};
