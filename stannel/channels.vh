`include "messages.vh"

// This file evolved independently of messages.vh, so these are mapped such that
// a core message, if it is a channel message, can be passed directly to the
// channel controller.
`define CREATE_CHANNEL  `CORE_MESSAGE_CREATE_CHANNEL
`define DESTROY_CHANNEL `CORE_MESSAGE_DELETE_CHANNEL
`define SEND_MESSAGE    `CORE_MESSAGE_SEND
`define RECEIVE_MESSAGE `CORE_MESSAGE_RECEIVE
`define ENABLE_CHANNEL  `CORE_MESSAGE_ENABLE_CHANNEL
`define DISABLE_CHANNEL `CORE_MESSAGE_DISABLE_CHANNEL
`define ALT_START       `CORE_MESSAGE_ALT_START
`define ALT_WAIT        `CORE_MESSAGE_ALT_WAIT
`define ALT_END         `CORE_MESSAGE_ALT_END
