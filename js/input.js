const keyState = [];

document.addEventListener("keydown", (e) => {
  keyState[e.keyCode] = true;
});
document.addEventListener("keyup", (e) => {
  keyState[e.keyCode] = false;
});
$canvasgl.addEventListener("blur", () => {
  console.log("blur");
  keyState.length = 0;
});
function isKeyDown(keyCode) {
  return keyState[keyCode] === true;
}

function isButtonDown(buttonIndex) {
  const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
  if (gamepads.length > 0) {
    const gamepad = gamepads.find((gamepad) => gamepad && gamepad.mapping === "standard");
    if (gamepad) {
      if (buttonIndex < gamepad.buttons.length) {
        return gamepad.buttons[buttonIndex].pressed;
      }
    }
  }
  return false;
}
function getAxis(axisIndex) {
  const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
  if (gamepads.length > 0) {
    const gamepad = gamepads.find((gamepad) => gamepad && gamepad.mapping === "standard");
    if (gamepad) {
      return gamepad.axes[axisIndex];
    }
  }
  return 0;
}

var input = {
  isKeyDown,
  isButtonDown,
  getAxis,
};
