// vad_web.js

function logMessage(message) {
  console.log(message);
}

let isListening = false;
let isPaused = false;
let vadInstance = null;

function startListeningImpl(
  positiveSpeechThreshold,
  negativeSpeechThreshold,
  preSpeechPadFrames,
  redemptionFrames,
  frameSamples,
  minSpeechFrames,
  submitUserSpeechOnPause,
  model,
  baseAssetPath,
  onnxWASMBasePath
) {
  // If already listening and not paused, return early
  if (isListening && !isPaused) return;

  // If we have an existing vadInstance and are paused, just resume
  if (vadInstance && isPaused) {
    console.log("Resuming VAD from paused state");
    vadInstance.start();
    isListening = true;
    isPaused = false;
    return;
  }

  // If we already have a vadInstance but not paused, return early
  if (vadInstance) return;

  isListening = true;
  isPaused = false;
  // Initialize and start VAD service
  async function initializeVAD() {
    try {
      vadInstance = await vad.MicVAD.new({
        positiveSpeechThreshold,
        negativeSpeechThreshold,
        preSpeechPadFrames,
        redemptionFrames,
        frameSamples,
        minSpeechFrames,
        submitUserSpeechOnPause,
        model,
        baseAssetPath,
        onnxWASMBasePath,
        onVADMisfire: () => {
          onVADMisfireCallback();
        },
        onSpeechStart: () => {
          onSpeechStartCallback();
        },
        onSpeechEnd: (audio) => {
          onSpeechEndCallback(audio);
        },
        onSpeechRealStart: () => {
          onRealSpeechStartCallback();
        },
        onFrameProcessed: (probabilities, frame) => {
          onFrameProcessedCallback(probabilities, frame);
        }
      });
      vadInstance.start();
    } catch (err) {
      onErrorCallback(err);
    }
  }
  initializeVAD();
}

function stopListeningImpl() {
  if (vadInstance !== null) {
    vadInstance.destroy();
    console.log("VAD instance stopped");
    isListening = false;
    isPaused = false;
    vadInstance = null;
  } else {
    onErrorCallback("VAD instance is not initialized");
  }
}

function pauseListeningImpl() {
  if (vadInstance !== null) {
    vadInstance.pause();
    console.log("VAD instance paused");
    isListening = false;
    isPaused = true;
  }
}

function isListeningNow() {
  return isListening;
}

const onErrorCallback = (error) => {
  if (typeof executeDartHandler === 'function') {
    if (error instanceof DOMException) {
      error = error.toString();
    }
    error = JSON.stringify({ error });
    executeDartHandler("onError", error);
  } else {
    console.error(error);
  }
};

const onSpeechEndCallback = (float32Array) => {
  const audioArray = Array.from(float32Array);
  const jsonData = JSON.stringify({ 
    audioData: audioArray,
  });
  
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onSpeechEnd", jsonData);
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onFrameProcessedCallback = (probabilities, frame) => {
  const frameArray = Array.from(frame);
  const jsonData = JSON.stringify({
    probabilities: {
      isSpeech: probabilities.isSpeech,
      notSpeech: probabilities.notSpeech
    },
    frame: frameArray
  });

  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onFrameProcessed", jsonData);
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onSpeechStartCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onSpeechStart", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};

const onRealSpeechStartCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onRealSpeechStart", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
}

const onVADMisfireCallback = () => {
  if (typeof executeDartHandler === 'function') {
    executeDartHandler("onVADMisfire", "");
  } else {
    onErrorCallback("executeDartHandler is not a function");
  }
};
