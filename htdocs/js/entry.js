var layout_mode = "wide";
var sc_old_border_style;
var column_two_rows = new Array();
var shift_init = "true";

function shift_contents() {
    if (! document.getElementById) return false;
    var infobox = document.getElementById('infobox');
    var column_one = document.getElementById('column_one_td');
    var column_two = document.getElementById('column_two_td');
    var column_one_table = document.getElementById('column_one_table');
    var column_two_table = document.getElementById("column_two_table");

    if (shift_init == "true") {
        column_two_rows[0] = document.getElementById('backdate_row');
        column_two_rows[1] = document.getElementById('comment_settings_row');
        column_two_rows[2] = document.getElementById('comment_screen_settings_row');
        if (document.getElementById('userpic_list_row') != null) {
            column_two_rows[3] = document.getElementById('userpic_list_row');
        }
        shift_init = "false";
    }

    var width;
    if (self.innerWidth) {       
	width = self.innerWidth;
    } else if (document.documentElement && document.documentElement.clientWidth) {
	width = document.documentElement.clientWidth;
    } else if (document.body) {
        width = document.body.clientWidth;
    }

    if (width < 1000) {
        if (layout_mode == "thin") { return; }
        layout_mode = "thin";
        sc_old_border_style = column_one.style.borderRight;
        column_one.style.borderRight = "0";
        column_two.style.display = "none";
        
        infobox.style.display = "none";
        for (var i = 0;  i < column_two_rows.length; i++) {
            column_one_table.lastChild.appendChild(column_two_rows[i]);        
        }
    } else {
        if (layout_mode == "wide") { return; }
        layout_mode = "wide";
        column_one.style.borderRight = sc_old_border_style;
        column_two.style.display = "block";
        
        infobox.style.display = "block";
        for (var i = 0;  i < column_two_rows.length; i++) {
            column_two_table.lastChild.appendChild(column_two_rows[i]);
        }
    }
    return;
}

function enable_rte () {
    if (! document.getElementById) return false;
    
    f = document.updateForm;
    if (! f) return false;
    f.switched_rte_on.value = 1;
    f.submit();
    return false;
}
// Maintain entry through browser navigations.
// IE does this onBlur, Gecko onUnload.
function save_entry () {
    if (! document.getElementById) return false;
    
    f = document.updateForm;
    if (! f) return false;
    rte = document.getElementById('rte');
    if (! rte) return false;
    content = document.getElementById('rte').contentWindow.document.body.innerHTML;
    f.saved_entry.value = content;
    return false;
}

// Restore saved_entry text across platforms.
// This is only used for IE, Gecko browser support is in the RTE library.
function restore_entry () {
    if (! document.getElementById) return false;
    f = document.updateForm;
    if (! f) return false;
    rte = document.getElementById('rte');
    if (! rte) return false;
    if (document.updateForm.saved_entry.value == "") return false;
    setTimeout(
               function () {
                   document.getElementById('rte').contentWindow.document.body.innerHTML = 
                       document.updateForm.saved_entry.value;
               }, 100);
    return false;
}

function pageload (dotime) {
    restore_entry();

    if (dotime) settime();
    if (!document.getElementById) return false;

    var remotelogin = document.getElementById('remotelogin');
    if (! remotelogin) return false;
    remotelogin.onclick = altlogin;

    f = document.updateForm;
    if (! f) return false;

    var userbox = f.user;
    if (! userbox) return false;
    if (userbox.value) altlogin();

    return false;
}

function customboxes (e) {
    if (! e) var e = window.event;
    if (! document.getElementById) return false;
    
    f = document.updateForm;
    if (! f) return false;
    
    var custom_boxes = document.getElementById('custom_boxes');
    if (! custom_boxes) return false;
    
    if (f.security.selectedIndex != 3) {
        custom_boxes.style.display = 'none';
        return false;
    }

    var altlogin_username = document.getElementById('altlogin_username');    
    if (altlogin_username != undefined && altlogin_username.style.display == 'table-row') {
        f.security.selectedIndex = 0;
        custom_boxes.style.display = 'none';
        alert("Custom security is only available when posting as the logged in user.");
    } else {
        custom_boxes.style.display = 'block';
    }
    
    if (e) {
        e.cancelBubble = true;
        if (e.stopPropagation) e.stopPropagation();
    }
    return false;
}

function altlogin (e) {
    if (! e) var e = window.event;
    if (! document.getElementById) return false;
    
    var altlogin_username = document.getElementById('altlogin_username');
    if (! altlogin_username) return false;
    altlogin_username.style.display = 'table-row';

    var altlogin_password = document.getElementById('altlogin_password');
    if (! altlogin_password) return false;
    altlogin_password.style.display = 'table-row';
    
    var remotelogin = document.getElementById('remotelogin');
    if (! remotelogin) return false;
    remotelogin.style.display = 'none';
    
    var usejournal_list = document.getElementById('usejournal_list');
    if (! usejournal_list) return false;
    usejournal_list.style.display = 'none';
    
    var userpic_list = document.getElementById('userpic_list_row');
    if (! userpic_list) return false;
    userpic_list.style.display = 'none';

    var userpic_preview = document.getElementById('userpic_preview');
    userpic_preview.style.display = 'none';

    var mood_preview = document.getElementById('mood_preview');
    mood_preview.style.display = 'none';
    
    f = document.updateForm;
    if (! f) return false;
    f.action = 'update.bml?altlogin=1';
    
    var custom_boxes = document.getElementById('custom_boxes');
    if (! custom_boxes) return false;
    custom_boxes.style.display = 'none';
    f.security.selectedIndex = 0;
    f.security.removeChild(f.security.childNodes[3]);

    if (e) {
        e.cancelBubble = true;
        if (e.stopPropagation) e.stopPropagation();
    }

    return false;    
}
function settime() {
    function twodigit (n) {
        if (n < 10) { return "0" + n; }
        else { return n; }
    }
    
    now = new Date();
    if (! now) return false;
    f = document.updateForm;
    if (! f) return false;
    
    f.date_ymd_yyyy.value = now.getYear() < 1900 ? now.getYear() + 1900 : now.getYear();
    f.date_ymd_mm.selectedIndex = twodigit(now.getMonth());
    f.date_ymd_dd.value = twodigit(now.getDate());
    f.hour.value = twodigit(now.getHours());
    f.min.value = twodigit(now.getMinutes());
    
    return false;
}
