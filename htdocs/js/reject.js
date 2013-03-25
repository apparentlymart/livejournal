;(function ($) {
    'use strict';

    $(function () {
        rejectFormManager.init();
    });

    var rejectFormManager = (function () {
        var config,
            _container,
            _hiddenWithIds,
            _removeControls,
            _userList,
            _submitButton,
            _returnLink;

        config = {
            containerSelector: '.b-pending',
            removeControlsSelector: '.i-pending-close',
            textareaSelector: '.b-pending-reason',
            hiddenWithIdsSelector: 'input[name=ids]',
            userListSelector: '.b-pending-users',
            submitButtonSelector: '.i-pending-reject',
            returnLinkSelector: '.i-pending-returnlink'
        };

        function findElems () {
            _container = $(config.containerSelector);
            _hiddenWithIds = _container.find(config.hiddenWithIdsSelector);
            _userList = _container.find(config.userListSelector);
            _removeControls = _userList.find(config.removeControlsSelector);
            _submitButton = _container.find(config.submitButtonSelector);
            _returnLink = _container.find(config.returnLinkSelector);
        }

        function bindRemoveUser () {
            _removeControls.bind('click', removeUser);
        }

        function removeUser(event) {
            var currentControl = $(this),
                elemToRemove = currentControl.closest('li'),
                userId = currentControl.attr('id').replace(/\D+/g, ''),
                userListLength = _userList.find('li').length;

            event.preventDefault();

            /*
            if (userListLength === 1) {
                return false;
            }
            */

            removeUserIdFromHidden(userId);

            elemToRemove.remove();

            if (userListLength === 1) {
                _returnLink.removeAttr('style');
                _submitButton.attr('disabled', true);
            } else {
                removeUnwantedCommas();
            }
        }

        function removeUnwantedCommas () {
            var lastUserElem,
                contentWithoutCommas;

            lastUserElem = _userList.find('li').last();
            contentWithoutCommas = lastUserElem.html().replace(/\,/g, '');
            lastUserElem
                .html(contentWithoutCommas)
                .find(config.removeControlsSelector)
                    .click(removeUser);
        }

        function removeUserIdFromHidden (userId) {
            var hiddenValue = _hiddenWithIds.val(),
                regExpToCheck = new RegExp('(' + userId + ')' + '(\,)*', 'g'),
                newHiddenValue = hiddenValue.replace(regExpToCheck, '');

            _hiddenWithIds.val(newHiddenValue);
        }

        function initPlaceholder () {
            var textarea = _container.find(config.textareaSelector);

            textarea.placeholder();
        }

        return {
            init : function () {
                findElems();
                bindRemoveUser();
                initPlaceholder();
            }
        };
    })();
}(jQuery));
