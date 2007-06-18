// add chal/resp auth to the "login" form if it exists
// this requires md5.js
LiveJournal.SetUpLoginForm = function () {
    var loginform = $("login");
    if (! loginform) return true;

    DOM.addEventListener(loginform, "submit", LiveJournal.LoginFormSubmitted.bindEventListener(loginform));
}

// When the login form is submitted, compute the challenge response and clear out the plaintext password field
LiveJournal.LoginFormSubmitted = function (loginform) {
    var chal_field = $("login_chal");
    var resp_field = $("login_response");
    var pass_field = $("xc_password");

    if (! chal_field || ! resp_field || ! pass_field)
        return true;

    var pass = pass_field.value;
    var chal = chal_field.value;
    var res = MD5(chal + MD5(pass));
    resp_field.value = res;
    pass_field.value = "";  // dont send clear-text password!
    return true;
}

LiveJournal.register_hook("page_load", LiveJournal.SetUpLoginForm);
