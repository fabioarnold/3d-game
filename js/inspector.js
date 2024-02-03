const inspectorElem = document.getElementById("inspector");

const inspectFloat = (namePtr, nameLen, valuePtr) => {
  const name = readCharStr(namePtr, nameLen);
  const floatMem = new Float32Array(memory.buffer, valuePtr, 3);
  let input = inspectorElem.querySelector("input#inspect_" + name);
  if (input === null) {
    // create input
    input = document.createElement("input");
    input.id = "inspect_" + name;
    input.type = "number";
    // input.step = "any";
    input.oninput = () => {
      const floatMem = new Float32Array(memory.buffer, valuePtr, 1);
      floatMem[0] = input.value;
    };
    const label = document.createElement("label");
    label.innerText = name + ":";
    inspectorElem.appendChild(label);
    inspectorElem.appendChild(input);
    inspectorElem.appendChild(document.createElement("br"));
  }
  if (document.activeElement !== input && input.value !== floatMem[0]) {
    input.value = floatMem[0];
  }
}

const inspectFloatRange = (namePtr, nameLen, valuePtr, min, max) => {
  const name = readCharStr(namePtr, nameLen);
  const floatMem = new Float32Array(memory.buffer, valuePtr, 1);
  let input = inspectorElem.querySelector("input#inspect_" + name);
  if (input === null) {
    // create input
    input = document.createElement("input");
    const output = document.createElement("output");
    input.id = "inspect_" + name;
    input.type = "range";
    input.step = "any";
    input.min = min;
    input.max = max;
    input.oninput = () => {
      const floatMem = new Float32Array(memory.buffer, valuePtr, 1);
      floatMem[0] = input.value;
      input.nextSibling.value = floatMem[0].toFixed(3);
    };
    const label = document.createElement("label");
    label.innerText = name + ":";
    inspectorElem.appendChild(label);
    inspectorElem.appendChild(input);
    inspectorElem.appendChild(output);
    inspectorElem.appendChild(document.createElement("br"));
  }
  if (document.activeElement !== input && input.value !== floatMem[0]) {
    input.value = floatMem[0];
    input.nextSibling.value = floatMem[0].toFixed(3); // update output
  }
};

const inspectVec3 = (namePtr, nameLen, valuePtr) => inspectVector(namePtr, nameLen, valuePtr, 3);

const inspectVector = (namePtr, nameLen, valuePtr, numComponents) => {
  const name = readCharStr(namePtr, nameLen);
  const floatMem = new Float32Array(memory.buffer, valuePtr, numComponents);
  let group = inspectorElem.querySelector("#inspect_" + name);
  if (group === null) {
    const label = document.createElement("label");
    label.innerText = name + ":";
    group = document.createElement("span");
    group.className = "group";
    group.id = "inspect_" + name;
    for (let i = 0; i < numComponents; i++) {
      const input = document.createElement("input");
      input.type = "number";
      input.step = "any";
      input.oninput = () => {
        const floatMem = new Float32Array(memory.buffer, valuePtr, numComponents);
        floatMem[i] = input.value;
      };
      group.appendChild(input);
    }
    inspectorElem.appendChild(label);
    inspectorElem.appendChild(group);
    inspectorElem.appendChild(document.createElement("br"));
  }
  for (let i = 0; i < numComponents; i++) {
    const input = group.children[i];
    if (document.activeElement !== input && input.value !== floatMem[i]) {
      input.value = floatMem[i];
    }
  }
}

var inspector = {
  inspectFloat,
  inspectFloatRange,
  inspectVec3,
};
