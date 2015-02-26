% [ed] = SliderParam(obj, parname, parval, min, max, x, y, varargin)
%
% Creates a slider SoloParamHandle of name given by parname, minimum
% value given by min, maximum by max, current value by parval, and with
% the lower left-hand corner of the slider's GUI at x, y. 
%
%   

function [ed] = SliderParam(obj, parname, parval, min, max, x, y, varargin)
   
   if ischar(obj) && strcmp(obj, 'base'), param_owner = 'base';
   elseif isobject(obj),                  param_owner = ['@' class(obj)];
   else   error('obj must be an object or the string ''base''');
   end;
   
   pairs = { ...
       'param_owner',        param_owner            ; ...
       'param_funcowner',    determine_fullfuncname     ; ...
       'position',           gui_position(x, y)         ; ...
       'TooltipString',      ''                         ; ...
       'minval',             min                        ; ...
       'maxval',             max                        ; ...
       'currval',            parval                     ; ...
       'label',              parname                    ; ...
       'labelfraction',      0.5                        ; ...
       'labelpos',           'right'                    ...  
       }; parseargs(varargin, pairs);
    
   ed = SoloParamHandle(obj, parname, ...
                        'type',            'slider', ...
                        'value',           currval,  ...
                        'minval',          minval,   ...
                        'maxval',          maxval,   ...
                        'position',        position, ...
                        'TooltipString',   TooltipString, ...
                        'label',           label, ...
                        'labelfraction',   labelfraction, ...
                        'labelpos',        labelpos, ...
                        'param_owner',     param_owner, ...
                        'param_funcowner', param_funcowner);
   assignin('caller', parname, eval(parname));
   return;
   
   