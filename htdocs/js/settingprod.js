function displaySettingProd(sett, fname, title) {
    if (! sett) return true;
    if (!title) {
        title = 'New Setting!';
    }
    var settingProd = new LJWidgetIPPU_SettingProd({
        title: title,
        }, {
            setting: sett,
            field: fname
        });
    settingProd.updateContent;

    return false;
}


