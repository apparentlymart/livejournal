function displaySettingProd(sett, fname) {
    if (! sett) return true;

    var settingProd = new LJWidgetIPPU_SettingProd({
        title: 'New Setting!',
        width: 320,
        height: 320
        }, {
            setting: sett,
            field: fname
        });
    settingProd.updateContent;

    return false;
}


