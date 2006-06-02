function useRichText(textArea, statPrefix) {
    if ($("insobj")) {
        $("insobj").className = 'display_none';
    }
    if ($("jrich")) {
        $("jrich").className = 'display_none';
    }
    if ($("jplain")) {
        $("jplain").className = '';
    }

    var editor_frame = $(textArea + '___Frame');

    // Check for RTE already existing.  IE will show multiple iframes otherwise.
    if (!editor_frame) {
        var oFCKeditor = new FCKeditor(textArea);
        oFCKeditor.BasePath = statPrefix + "/fck/";
        oFCKeditor.Height = 350;
        oFCKeditor.ToolbarSet = "Update";
        if ($("event_format") && $("event_format").selectedIndex == 0) {
            $(textArea).value = $(textArea).value.replace(/\n/g, '<br />');
        }
        oFCKeditor.ReplaceTextarea();
    } else {
        var oEditor = FCKeditorAPI.GetInstance(textArea);
        editor_frame.style.display = "block";
        $(textArea).style.display = "none";
        var editor_source = editor_frame.contentWindow.document.getElementById('eEditorArea');
        if ($("event_format") && $("event_format").selectedIndex == 0) {
            $(textArea).value = $(textArea).value.replace(/\n/g, '<br />');
        }
        editor_source.contentWindow.document.body.innerHTML = $(textArea).value;

        // Allow RTE to use it's handler again so it's happy.
        var oForm = oEditor.LinkedField.form;
        DOM.addEventListener( oForm, 'submit', oEditor.UpdateLinkedField, true ) ;
        oForm.originalSubmit = oForm.submit;
        oForm.submit = oForm.SubmitReplacer;
    }

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

function usePlainText(textArea) {
    if (! FCKeditorAPI) return;
    var oEditor = FCKeditorAPI.GetInstance(textArea);
    if (! oEditor) return;
    var editor_frame = $(textArea + '___Frame');
    var editor_source = editor_frame.contentWindow.document.getElementById('eEditorArea'); 

    var html = oEditor.GetXHTML();
    //    if ($("event_format") && $("event_format").selectedIndex == 0) {
        html = html.replace(/\<br \/\>/g, '\n');
        html = html.replace(/\<p\>(.+)\<\/p\>/g, '$1\n');
        html = html.replace(/&nbsp;/g, ' ');
        //    }
    $(textArea).value = html;

    if ($("insobj"))
        $("insobj").className = '';
    if ($("jrich"))
        $("jrich").className = '';
    if ($("jplain"))
        $("jplain").className = 'display_none';

    editor_frame.style.display = "none";
    $(textArea).style.display = "block";

    $("switched_rte_on").value = '0';

    // Remove onsubmit handler while in Plain text
    var oForm = oEditor.LinkedField.form;
    DOM.removeEventListener( oForm, 'submit', oEditor.UpdateLinkedField, true ) ;
    oForm.SubmitReplacer = oForm.submit;
    oForm.submit = oForm.originalSubmit;
    return false;
}
