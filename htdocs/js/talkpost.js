
var usernameWasFocused = 0;

if (document.getElementById) {
    // If there's no getElementById, this whole script won't do anything

    var radio_remote = document.getElementById("talkpostfromremote");
    var radio_user = document.getElementById("talkpostfromlj");
    var radio_anon = document.getElementById("talkpostfromanon");

    var check_login = document.getElementById("logincheck");
    var sel_pickw = document.getElementById("prop_picture_keyword");
    var commenttext = document.getElementById("commenttext");

    var form = document.getElementById("postform");

    var username = form.userpost;
    username.onfocus = function () { usernameWasFocused = 1; }
    var password = form.password;

    var remotef = document.getElementById("cookieuser");
    var remote;
    if (remotef) {
        remote = remotef.value;
    }

    var subjectIconField = document.getElementById("subjectIconField");
    var subjectIconImage = document.getElementById("subjectIconImage");
}

var apicurl = "";
var picprevt;

if (! sel_pickw) {
    // make a fake sel_pickw to play with later
    sel_pickw = new Object();
}

function handleRadios(sel) {
    password.disabled = check_login.disabled = (sel != 2);
    if (password.disabled) password.value='';
    if (sel_pickw.disabled = (sel != 1)) sel_pickw.value='';
}

function submitHandler() {
    if (remote && username.value == remote && (! radio_anon || ! radio_anon.checked)) {
        //  Quietly arrange for cookieuser auth instead, to avoid
        // sending cleartext password.
        password.value = "";
        username.value = "";
        radio_remote.checked = true;
        return true;
    }
    if (usernameWasFocused && username.value && ! radio_user.checked) {
        alert(usermismatchtext);
        return false;
    }
    if (! radio_user.checked) {
        username.value = "";
    }
    return true;
}

if (document.getElementById) {

    if (radio_anon && radio_anon.checked) handleRadios(0);
    if (radio_user && radio_user.checked) handleRadios(2);

    if (radio_remote) {
        radio_remote.onclick = function () {
            handleRadios(1);
        };
        if (radio_remote.checked) handleRadios(1);
    }
    if (radio_user)
        radio_user.onclick = function () {
            handleRadios(2);
        };
    if (radio_anon)
        radio_anon.onclick = function () {
            handleRadios(0);
        };
    username.onkeydown = username.onchange = function () {
        if (radio_user && username.value != "")
            radio_user.checked = true;
        handleRadios(2);  // update the form
    }
    form.onsubmit = submitHandler;

    document.onload = function () {
        if (radio_anon && radio_anon.checked) handleRadios(0);
        if (radio_user && radio_user.checked) handleRadios(2);
        if (radio_remote && radio_remote.checked) handleRadios(1);
    }

}

// toggle subject icon list

function subjectIconListToggle() {
    if (! document.getElementById) { return; }
    var subjectIconList = document.getElementById("subjectIconList");
    if(subjectIconList) {
     if (subjectIconList.style.display != 'block') {
         subjectIconList.style.display = 'block';
     } else {
         subjectIconList.style.display = 'none';
     }
    }
}

// change the subject icon and hide the list

function subjectIconChange(icon) {
    if (! document.getElementById) { return; }
    if (icon) {
        if(subjectIconField) subjectIconField.value=icon.id;
        if(subjectIconImage) {
            subjectIconImage.src=icon.src;
            subjectIconImage.width=icon.width;
            subjectIconImage.height=icon.height;
        }
        subjectIconListToggle();
    }
}

