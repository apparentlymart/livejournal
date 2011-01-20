(function ($) {
	$(function () {
		rejectFormManager.init();
	});
	
	var rejectFormManager = (function () {
		var CONFIG = {
			containerSelector : '.b-pending',
			removeControlsSelector : '.i-pending-close',
			textareaSelector : '.b-pending-reason',
			hiddenWithIdsSelector : 'input[name=ids]',
			userListSelector : '.b-pending-users',
			submitButtonSelector : '.i-pending-reject',
			returnLinkSelector : '.i-pending-returnlink'
		};
		
		var _container, _hiddenWithIds, _removeControls, _userList;
		
		function findElems () {
			_container = $(CONFIG.containerSelector);
			_hiddenWithIds = _container.find(CONFIG.hiddenWithIdsSelector);
			_userList = _container.find(CONFIG.userListSelector);
			_removeControls = _userList.find(CONFIG.removeControlsSelector);
			_submitButton = _container.find(CONFIG.submitButtonSelector);
			_returnLink = _container.find(CONFIG.returnLinkSelector);
		}
		
		function bindRemoveUser () {
			_removeControls.bind('click', removeUser);
		}
		
		function removeUser (event) {
			event.preventDefault();
			
			var currentControl = $(this),
				elemToRemove = currentControl.closest('li'),
				userId = currentControl.attr('id').replace(/\D+/g, ''),
				userListLength = _userList.find('li').length;
				
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
			var userListLength = _userList.find('li').length,
				lastUserElem, lastUserContent;
			
			lastUserElem = _userList.find('li').last();
			contentWithoutCommas = lastUserElem.html().replace(/\,/g, '');
			lastUserElem
				.html(contentWithoutCommas)
				.find(CONFIG.removeControlsSelector)
					.click(removeUser);
		}
		
		function removeUserIdFromHidden (userId) {
			var hiddenValue = _hiddenWithIds.val(),
				regExpToCheck = new RegExp('(' + userId + ')' + '(\,)*', 'g'),
				newHiddenValue = hiddenValue.replace(regExpToCheck, '');
			
			_hiddenWithIds.val(newHiddenValue);
		}
		
		function initPlaceholder () {
			var textarea = _container.find(CONFIG.textareaSelector);
			
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
})(jQuery);
