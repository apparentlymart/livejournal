function photobucket_complete(inurl, width, height)
{
    if(window.top && window.top.InOb) {
        window.top.InOb.onInsURL(inurl, width, height);
        setTimeout(function () { window.parent.InOb.onClosePopup(); }, 100);
    }
    if(window.top && window.top.CKEDITOR) {
        var dialog = window.top.CKEDITOR.dialog.getCurrent();
        if (dialog) {
            dialog.hide();
        }
    }
}
