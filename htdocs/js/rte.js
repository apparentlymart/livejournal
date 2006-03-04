function useRichText(textArea, statPrefix) {
    if ($("insobj")) {
        $("insobj").className = 'display_none';
    }
    if ($("jrich")) {
        $("jrich").className = 'display_none';
    }
    var oFCKeditor = new FCKeditor(textArea);
    oFCKeditor.BasePath = statPrefix + "/fck/";
    oFCKeditor.Height = 350;
    oFCKeditor.ToolbarSet = "Update";

    if ($("event_format").selectedIndex == 0) {
        $("draft").value = $("draft").value.replace(/\n/g, '<br />');
    }

    oFCKeditor.ReplaceTextarea();

    // Need to pause here as it takes some time for the editor
    // to actually load within the browser before we can
    // access it.
    setTimeout("RTEAddClasses('" + textArea + "', '" + statPrefix + "')", 2000);

    $("switched_rte_on").value = '1';
    return false; // do not follow link
}

function RTEAddClasses(textArea, statPrefix) {
    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;

    var html = oEditor.GetXHTML();

    html = html.replace(/<lj-cut>(.+?)<\/lj-cut>/g, '<div class="ljcut">$1</div>');
    html = html.replace(/<lj-raw>([\w\s]+?)<\/lj-raw>/g, '<lj-raw class="ljraw">$1</lj-raw>');

    html = html.replace(/<lj user=['"](\w+)["'] ?\/?>/g, "<span class='ljuser'><img src='" + statPrefix + "/fck/editor/plugins/livejournal/userinfo.gif' width='17' height='17' style='vertical-align: bottom' />$1</span>");

    oEditor.SetHTML(html);
}
