export function openDialog(application, dialog) {
  const controller = dialogController(application, dialog);
  if (controller) {
    controller.open();
  } else if (!dialog.open) {
    dialog.showModal();
  }
}

export function closeDialog(application, dialog) {
  const controller = dialogController(application, dialog);
  if (controller) {
    controller.close();
  } else if (dialog.open) {
    dialog.close();
  }
}

function dialogController(application, dialog) {
  return application.getControllerForElementAndIdentifier(dialog, "DS--dialog");
}
