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
			userListSelector : '.b-pending-users'
		};
		
		var _containter, _hiddenWithIds, _removeControls, _userList;
		
		function findElems () {
			_container = $(CONFIG.containerSelector);
			_hiddenWithIds = _container.find(CONFIG.hiddenWithIdsSelector);
			_userList = _container.find(CONFIG.userListSelector);
			_removeControls = _userList.find(CONFIG.removeControlsSelector);
		}
		
		function bindRemoveUser () {
			_removeControls.bind('click', removeUser);
		}
		
		function removeUser (event) {
			event.preventDefault();
			
			var currentControl = $(this),
				elemToRemove = currentControl.closest('li'),
				userId = currentControl.attr('id').replace(/\D+/g, '');
			
			removeUserIdFromHidden(userId);
			
			elemToRemove.remove();
			removeUnwantedCommas();
		}
		
		function removeUnwantedCommas () {
			var userListLength = _userList.find('li').length,
				firstUserElem, firstUserContent;
			
			if (userListLength === 1) {
				firstUserElem = _userList.first();
				contentWithoutCommas = firstUserElem.html().replace(/\,/g, '');
				firstUserElem.html(contentWithoutCommas);
			}
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
