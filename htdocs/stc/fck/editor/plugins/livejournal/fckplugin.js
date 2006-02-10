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
    var selection = FCK.EditorWindow.getSelection();

    if (selection != '') {
        user = selection;
    } else {
        user = prompt('Enter their username', '');
    }

    if (user != null && user != '') {
        if (! this.validUsername(user)) {
            alert('Invalid characters in username');
            return;
        }

        // Make the tag like the editor would and apply formatting
        var html = "<lj user=''>";
        html    += "<span class='LJUser'>";
        html    += "<img src='" + FCKConfig.PluginsPath + "livejournal/userinfo.gif' width='17' height='17' style='vertical-align: bottom' />";
        html    += user;
        html    += "</span></lj>";

        FCK.InsertHtml(html);
    }
    return;
}

FCKCommands.RegisterCommand('LJUserLink', LJUserCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJUserLink = new FCKToolbarButton('LJUserLink', 'LiveJournal User');
oLJUserLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljuser.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJUserLink', oLJUserLink) ;

//////////  LJ Cut Button //////////////
var LJCutCommand=function(){
};
LJCutCommand.prototype.Execute=function(){
}
LJCutCommand.GetState=function() {
    return FCK_TRISTATE_OFF; //we dont want the button to be toggled
}

LJCutCommand.Execute=function() {
    var selection = FCK.EditorWindow.getSelection();

    if (selection != '') {
        selection += ''; // Cast it to a string
        selection = selection.replace(/\n/g, '<br />');

        var html = "<lj-cut class='LJCut'>";
        html    += selection;
        html    += "</lj-cut>";

        FCK.InsertHtml(html);
    }
    return;
}

FCKCommands.RegisterCommand('LJCutLink', LJCutCommand ); //otherwise our command will not be found

// Create the toolbar button.
var oLJCutLink = new FCKToolbarButton('LJCutLink', 'LiveJournal Cut');
oLJCutLink.IconPath = FCKConfig.PluginsPath + 'livejournal/ljcut.gif' ;

// Register the button to use in the config
FCKToolbarItems.RegisterItem('LJCutLink', oLJCutLink) ;
