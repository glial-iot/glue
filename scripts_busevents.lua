#!/usr/bin/env tarantool
local busevents = {}
local busevents_private = {}

local box = box
local http_system = require 'http_system'

local inspect = require 'libs/inspect'

local logger = require 'logger'
local config = require 'config'
local system = require 'system'
local scripts = require 'scripts'
local fiber = require 'fiber'

local busevents_main_scripts_table = {}

local function log_bus_event_error(msg, uuid)
   logger.add_entry(logger.ERROR, "Bus-events subsystem", msg, uuid, "")
end

local function log_bus_event_warning(msg, uuid)
   logger.add_entry(logger.WARNING, "Bus-events subsystem", msg, uuid, "")
end

local function log_bus_event_info(msg, uuid)
   logger.add_entry(logger.INFO, "Bus-events subsystem", msg, uuid, "")
end

------------------ Private functions ------------------


function busevents_private.load(uuid, run_once_flag)
   local body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_bus_event_error('Attempt to start non-busevent script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (script_params.uuid == nil) then
      log_bus_event_error('Web-event "'..script_params.name..'" not start (not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Not found'})
      return false
   end

   if (script_params.body == nil) then
      log_bus_event_error('Web-event "'..script_params.name..'" not start (body nil)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: No body'})
      return false
   end

   if ((script_params.active_flag == nil or script_params.active_flag ~= scripts.flag.ACTIVE) and run_once_flag ~= true) then
      log_bus_event_info('Web-event "'..script_params.name..'" not start (non-active)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Non-active'}) -- TODO: не работает без перезагрузки
      return true
   end

   local current_func, error_msg = loadstring(script_params.body, script_params.name)

   if (current_func == nil) then
      log_bus_event_error('Web-event "'..script_params.name..'" not start (body load error: '..(error_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: Body load error: '..(error_msg or "")})
      return false
   end

   local log_script_name = "Bus event '"..(script_params.name or "undefined name").."'"
   body = scripts.generate_body(script_params, log_script_name)

   local status, err_msg = pcall(setfenv(current_func, body))
   if (status ~= true) then
      log_bus_event_error('Bus-event "'..script_params.name..'" not start (load error: '..(err_msg or "")..')', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: pcall error: '..(err_msg or "")})
      return false
   end

   if (body.event_handler == nil or type(body.event_handler) ~= "function") then
      log_bus_event_error('Bus-event "'..script_params.name..'" not start ("event_handler" function not found or no function)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: "event_handler" function not found or no function'})
      return false
   end

   if ((script_params.object == nil or script_params.object == "") and type(script_params.object) == "string") then
      log_bus_event_error('Bus-event "'..script_params.name..'" not start (mask not found)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: mask not found'})
      return false
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not start (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: destroy not function'})
         return false
      end
   end

   if (body.init ~= nil and run_once_flag ~= true) then
      if (type(body.init) ~= "function") then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not start (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init not function'})
         return false
      end

      local init_status, init_returned_data = pcall(body.init)

      if (init_status ~= true) then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not start (init function error: '..(init_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Start: init function error: '..(init_returned_data or "")})
         return false
      end
   end

   if (run_once_flag == true) then
      log_bus_event_info('Bus-event "'..script_params.name..'" runned once', script_params.uuid)
      local value = 0
      local topic = "once"
      local pcall_status, returned_data = pcall(body.event_handler, value, topic)
      if (pcall_status ~= true) then
         returned_data = tostring(returned_data)
         log_bus_event_error('Bus-event "'..script_params.name..'" generate error: '..(returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Event: error: '..(returned_data or "")})
      end
   else
      busevents_main_scripts_table[uuid] = nil
      busevents_main_scripts_table[uuid] = {}
      busevents_main_scripts_table[uuid].body = body
      busevents_main_scripts_table[uuid].mask = script_params.object

      log_bus_event_info('Bus-event "'..script_params.name..'" active on mask "'..(script_params.object or "")..'"', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.NORMAL, status_msg = 'Active on mask "'..(script_params.object or "")..'"'})
   end

   return true
end

function busevents_private.unload(uuid)
   local body = busevents_main_scripts_table[uuid].body
   local script_params = scripts.get({uuid = uuid})

   if (script_params.type ~= scripts.type.BUS_EVENT) then
      log_bus_event_error('Attempt to stop non-bus-event script "'..script_params.name..'"', script_params.uuid)
      return false
   end

   if (body == nil) then
      log_bus_event_error('Bus-event script "'..script_params.name..'" not stop (script body error)', script_params.uuid)
      scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: script body error'})
      return false
   end

   if (body.init ~= nil) then
      if (type(body.init) ~= "function") then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not stop (init not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: init not function'})
         return false
      end
   end

   if (body.destroy ~= nil) then
      if (type(body.destroy) ~= "function") then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not stop (destroy not function)', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy not function'})
         return false
      end

      local destroy_status, destroy_returned_data = pcall(body.destroy)
      if (destroy_status ~= true) then
         log_bus_event_error('Bus-event script "'..script_params.name..'" not stop (destroy function error: '..(destroy_returned_data or "")..')', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.ERROR, status_msg = 'Stop: destroy function error: '..(destroy_returned_data or "")})
         return false
      end
      if (destroy_returned_data == false) then
         log_bus_event_warning('Bus-event script "'..script_params.name..'" not stopped, need restart glue', script_params.uuid)
         scripts.update({uuid = uuid, status = scripts.statuses.WARNING, status_msg = 'Not stopped, need restart glue'})
         return false
      end
   end

   log_bus_event_info('Bus-event script "'..script_params.name..'" set status to non-active', script_params.uuid)
   scripts.update({uuid = uuid, status = scripts.statuses.STOPPED, status_msg = 'Not active'})
   busevents_main_scripts_table[uuid] = nil
   return true
end



function busevents_private.http_api(req)
   local params = req:param()
   local return_object
   if (params["action"] == "reload") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         local data = scripts.get({uuid = params["uuid"]})
         if (data.status == scripts.statuses.NORMAL or data.status == scripts.statuses.WARNING) then
            local result = busevents_private.unload(params["uuid"])
            if (result == true) then
               busevents_private.load(params["uuid"], false)
            end
         else
            busevents_private.load(params["uuid"], false)
         end
         return_object = req:render{ json = {result = true} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Busevents API: No valid UUID"} }
      end
   elseif (params["action"] == "run_once") then
      if (params["uuid"] ~= nil and params["uuid"] ~= "") then
         busevents_main_scripts_table[params["uuid"]] = nil
         busevents_private.load(params["uuid"], true)
         busevents_main_scripts_table[params["uuid"]] = nil
         return_object = req:render{ json = {result = true} }
      else
         return_object = req:render{ json = {result = false, error_msg = "Busevents API: No valid UUID"} }
      end
   else
      return_object = req:render{ json = {result = false, error_msg = "Busevents API: No valid action"} }
   end

   return_object = return_object or req:render{ json = {result = false, error_msg = "Busevents API: Unknown error(435)"} }
   return system.add_headers(return_object)
end

------------------ Public functions ------------------

function busevents.process(topic, value, source_uuid)
   for uuid, current_script_table in pairs(busevents_main_scripts_table) do
      local script_params = scripts.get({uuid = uuid})
      if (script_params.status == scripts.statuses.NORMAL and
         script_params.active_flag == scripts.flag.ACTIVE and
         script_params.uuid ~= (source_uuid or "0")) then
         local mask = current_script_table.mask
         if (string.find(topic, mask) ~= nil) then
            local event_handler = current_script_table.body.event_handler
            local status, returned_data = pcall(event_handler, value, topic)
            if (status ~= true) then
               returned_data = tostring(returned_data)
               log_bus_event_error('Bus-event "'..script_params.name..'" generate error: '..(returned_data or "")..')', script_params.uuid)
               scripts.update({uuid = script_params.uuid, status = scripts.statuses.ERROR, status_msg = 'Event: error: '..(returned_data or "")})
            end
            return returned_data
         end
         fiber.yield()
      end
      fiber.yield()
   end
end

function busevents.init()
   busevents.start_all()
   http_system.endpoint_config("/busevents", busevents_private.http_api)
end

function busevents.start_all()
   local list = scripts.get_all({type = scripts.type.BUS_EVENT})

   for _, busevent in pairs(list) do
      busevents_private.load(busevent.uuid)
      fiber.yield()
   end
end

return busevents
