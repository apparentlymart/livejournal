// JavaScript Unit Testing Extension
// http://fireunit.org/

// "lj @user", "lj @user @title", test machine
fireunit.compare(convert_user_to_ljtags('\
    <div class="ljuser"><a href="http://test.lj-10.bulyon.local/profile"><img width="17" height="17" src="http://www.lj-10.bulyon.local/img/userinfo.gif" alt="[info]" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" /></a><a href="http://test.lj-10.bulyon.local/"><b>test</b></a></div><div class="ljuser"><a href="http://test.lj-10.bulyon.local/profile"><img width="17" height="17" src="http://www.lj-10.bulyon.local/img/userinfo.gif" alt="[info]" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" /></a><a href="http://test.lj-10.bulyon.local/"><b>elk\s\'wlk;w</b></a></div>\
    <br />\
    <div class="ljuser"><a href="http://test.lj-10.bulyon.local/profile"><img width="17" height="17" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" alt="[info]" src="http://www.lj-10.bulyon.local/img/userinfo.gif" /></a><a href="http://test.lj-10.bulyon.local/"><b>test</b></a></div>')
    ,
    '\
    <lj user="test"/><lj user="test" title="elk\s\'wlk;w"/>\
    <br />\
    <lj user="test"/>',
    'ljuser"');

// username with "_"
fireunit.compare(convert_user_to_ljtags('\
    <div class="ljuser"><a href="http://ki-zu.livejournal.com/profile"><img width="17" height="17" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" alt="[info]" src="http://l-stat.livejournal.com/img/userinfo.gif" /></a><a href="http://ki-zu.livejournal.com/"><b>ki_zu</b></a></div>\
    <br />\
    <div class="ljuser"><a href="http://ki-zu.livejournal.com/profile"><img width="17" height="17" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" alt="[info]" src="http://l-stat.livejournal.com/img/userinfo.gif" /></a><a href="http://ki-zu.livejournal.com/"><b>ki-zu</b></a></div>')
    ,
    '\
    <lj user="ki_zu"/>\
    <br />\
    <lj user="ki_zu" title="ki-zu"/>',
    'ljuser"');

// username start with "_"
fireunit.compare(convert_user_to_ljtags('\
    <div class="ljuser"><a href="http://users.livejournal.com/__h4__/profile"><img width="17" height="17" src="http://l-stat.livejournal.com/img/userinfo.gif" alt="[info]" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" /></a><a href="http://users.livejournal.com/__h4__/"><b>__h4__</b></a></div>\
    <br />\
    <div class="ljuser"><a href="http://akella_art.livejournal.com/profile"><img width="17" height="17" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" alt="[info]" src="http://l-stat.livejournal.com/img/userinfo.gif" /></a><a href="http://akella_art.livejournal.com/"><b>akella</b></a></div>')
    ,
    '\
    <lj user="__h4__"/>\
    <br />\
    <lj user="akella_art" title="akella"/>',
    'ljuser"');

// community
fireunit.compare(convert_user_to_ljtags('\
    <div class="ljuser"><a href="http://community.lj-10.bulyon.local/lj_core/profile"><img width="17" height="17" src="http://www.lj-10.bulyon.local/img/community.gif" alt="[info]" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" /></a><a href="http://community.lj-10.bulyon.local/lj_core/"><b>lj_core</b></a></div>\
    <br />\
    lj_core\
    <br />\
    <div class="ljuser"><a href="http://community.livejournal.com/changelog/profile"><img width="16" height="16" style="border: 0pt none ; vertical-align: bottom; padding-right: 1px;" alt="[info]" src="http://l-stat.livejournal.com/img/community.gif"/></a><a href="http://community.livejournal.com/changelog/"><b>changelog "2 test</b></a></div>')
    ,
    '\
    <lj comm="lj_core"/>\
    <br />\
    lj_core\
    <br />\
    <lj comm="changelog" title="changelog \"2 test"/>',
    'ljuser"');



fireunit.testDone();
