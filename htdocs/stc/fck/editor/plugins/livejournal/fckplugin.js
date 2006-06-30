
//////////  LJ User Button //////////////
var LJUserCommand=function(){
};
LJUserCommand.prototype.Execute=function(){
}
LJUserCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

// Check for allowed lj user characters
LJUserCommand.validUsername = function(str) {
    var pattern = /^\w{1,15}$/i;
    return pattern.test(str);
}

LJUserCommand.Execute=function() {
    var user;
    var selection = '';

    if (FCK.EditorWindow.getSelection) {
        selection = FCK.EditorWindow.getSelection();
    } else if (FCK.EditorDocument.selection) {
        selection = FCK.EditorDocument.selection.createRange().text;
    }

    if (selection != '') {
        user = selection;
    } else {
        user = prompt(window.parent.FCKLang.UserPrompt, '');
    }

    if (user != null && user != '') {
        if (! this.validUsername(user)) {
            alert(window.parent.FCKLang.InvalidChars);
            return;
        }

        // Make the tag like the editor would and apply formatting
        var html = "<span class='ljuser'>";
        html     += "<img width='17' height='17' alt='' src='" + FCKConfig.PluginsPath + "livejournal/userinfo.gif' style='vertical-align: bottom' />";
        html     += user;
        html     += "</span>";

        FCK.InsertHtml(html);
        FCK.Focus();
    }
    return;
}

FCKCommands.RegisterCommand('LJUserLink', LJUserCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJUserLink = new FCKToolbarButton('LJUserLink', window.parent.FCKLang.LJUser);
oLJUserLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljuser.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJUserLink', oLJUserLink) ;


//////////  LJ Video Button //////////////
var LJVideoCommand=function(){
};
LJVideoCommand.prototype.Execute=function(){
}
LJVideoCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJVideoCommand.Execute=function() {
    var url;
    var selection = '';

    if (FCK.EditorWindow.getSelection) {
        selection = FCK.EditorWindow.getSelection();
    } else if (FCK.EditorDocument.selection) {
        selection = FCK.EditorDocument.selection.createRange().text;
    }
    if (selection != '') {
        url = selection;
    } else {
        url = prompt(window.parent.FCKLang.VideoPrompt,'');
    }

    if (url != null && url != '') {
        // Make the tag like the editor would
        var html = "<span class='ljvideo'>";
        html += url;
        html += "</span>";

        FCK.InsertHtml(html);
        FCK.Focus();
    }
    return;
}

FCKCommands.RegisterCommand('LJVideoLink', LJVideoCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJVideoLink = new FCKToolbarButton('LJVideoLink', window.parent.FCKLang.LJVideo);
oLJVideoLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljvideo.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJVideoLink', oLJVideoLink) ;

//////////  LJ Cut Button //////////////
var LJCutCommand=function(){
};
LJCutCommand.prototype.Execute=function(){
}
LJCutCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJCutCommand.Execute=function() {
    var text = prompt(window.parent.FCKLang.CutPrompt, window.parent.FCKLang.ReadMore);
    if (text == window.parent.FCKLang.ReadMore) {
        text = '';
    } else {
        text = text.replace('"', '\"');
        text = ' text="' + text + '"';
    }

    var selection = '';

    if (FCK.EditorWindow.getSelection) {
        selection = FCK.EditorWindow.getSelection();

        // Create a new div to clone the selection's content into
        var d = FCK.EditorDocument.createElement('DIV');
        for (var i = 0; i < selection.rangeCount; i++) {
            d.appendChild(selection.getRangeAt(i).cloneContents());
        }
        selection = d.innerHTML;

    } else if (FCK.EditorDocument.selection) {
        var range = FCK.EditorDocument.selection.createRange();

        var type = FCKSelection.GetType();
        if (type == 'Control') {
            selection = range.item(0).outerHTML;
        } else if (type == 'None') {
            selection = '';
        } else {
            selection = range.htmlText;
        }
    }

    if (selection != '') {
        selection += ''; // Cast it to a string
    } else {
        selection += window.parent.FCKLang.CutContents;
    }

    var html = "<div class='ljcut'" +  text + ">";
    html    += selection;
    html    += "</div>";

    FCK.InsertHtml(html);
    FCK.Focus();

    return;
}

FCKCommands.RegisterCommand('LJCutLink', LJCutCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJCutLink = new FCKToolbarButton('LJCutLink', window.parent.FCKLang.LJCut);
oLJCutLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljcut.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJCutLink', oLJCutLink) ;
