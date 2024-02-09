const readCharStr = (ptr, len) => {
    const array = new Uint8Array(memory.buffer, ptr, len)
    const decoder = new TextDecoder()
    return decoder.decode(array)
}

const performanceNow = () => performance.now();

let log_string = '';

const wasm_log_write = (ptr, len) => {
    log_string += readCharStr(ptr, len)
}

const wasm_log_flush = () => {
    console.log(log_string)
    log_string = ''
}

var wasm = {
    performanceNow,
    wasm_log_write,
    wasm_log_flush,
};