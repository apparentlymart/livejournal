//= require js/widget_ippu/settingprod.js

function displaySettingProd(sett, fname, title, options) {
    if (!sett) return true;
    if (!title) title = 'New Setting!';
    if (!options) options = {}

    window.settingProd = new LJWidgetIPPU_SettingProd({
        title: title,
        center: true,
        not_view_close: options.close === false ? true : false // options.close may be undefined, default - true
        },{
            setting: sett,
            field: fname
        });
    return false;
}
