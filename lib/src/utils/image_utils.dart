// Image compression, base64 encoding, and cropping utilities.
// All heavy operations must be dispatched via compute() to avoid UI jank.
// Target output: JPEG < 1MB before base64 encoding.
