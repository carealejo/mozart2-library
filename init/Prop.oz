%%%
%%% Authors:
%%%   Denys Duchier (duchier@ps.uni-sb.de)
%%%
%%% Copyright:
%%%   Denys Duchier, 1998
%%%
%%% Last change:
%%%   $Date$ by $Author$
%%%   $Revision$
%%%
%%% This file is part of Mozart, an implementation
%%% of Oz 3
%%%    $MOZARTURL$
%%%
%%% See the file "LICENSE" or
%%%    $LICENSEURL$
%%% for information on usage and redistribution
%%% of this file, and for a DISCLAIMER OF ALL
%%% WARRANTIES.
%%%

%%% Here we initialize all system properties
%%%
%%% oz.home             OZHOME  OZ_HOME
%%% oz.search.path      OZPATH  OZ_PATH  OZ_SEARCH_PATH
%%% oz.search.load      OZLOAD  OZ_LOAD  OZ_SEARCH_LOAD
%%% oz.search.dload     OZDLOAD OZ_DLOAD OZ_SEARCH_DLOAD
%%% os.name
%%% os.cpu (os.arch)
%%% path.separator      OZ_PATH_SEPARATOR
%%% path.escape         OZ_PATH_ESCAPE (to escape a path separator)
%%% user.home           HOME

OS_NAME         = {GET 'os.name'}
OS_CPU          = {GET 'os.cpu'}
%OS_NAME#OS_CPU = {{`Builtin` 'SystemGetPlatform' 1}}

PATH_SEPARATOR  = case {Getenv 'OZ_PATH_SEPARATOR'} of [C] then C
                  elsecase OS_NAME of win32 then &; else &: end

PATH_ESCAPE     = case {Getenv 'OZ_PATH_ESCAPE'} of [C] then C
                  elsecase OS_NAME of win32 then unit else &\\ end

OZ_HOME         = case {Getenv 'OZ_HOME'} of false then
                     case {Getenv 'OZHOME'} of false then
                        {{`Builtin` 'SystemGetHome' 1}}
                     elseof V then V end
                  elseof V then V end

OZ_SEARCH_PATH  = case {Getenv 'OZ_SEARCH_PATH'} of false then
                     case {Getenv 'OZ_PATH'} of false then
                        case {Getenv 'OZPATH'} of false then
                           '.'#[PATH_SEPARATOR]#OZ_HOME#'/lib'
                        elseof V then V end
                     elseof V then V end
                  elseof V then V end

OZ_SEARCH_LOAD  = case {Getenv 'OZ_SEARCH_LOAD'} of false then
                     case {Getenv 'OZ_LOAD'} of false then
                        case {Getenv 'OZLOAD'} of false then
                           'cache='#OZ_HOME#'/cache'
                        elseof V then V end
                     elseof V then V end
                  elseof V then V end

OZ_SEARCH_DLOAD = case {Getenv 'OZ_SEARCH_DLOAD'} of false then
                     case {Getenv 'OZ_DLOAD'} of false then
                        case {Getenv 'OZDLOAD'} of false then
                           '.:'#OZ_HOME#'/platform/'#OS_NAME#'-'#OS_CPU
                        elseof V then V end
                     elseof V then V end
                  elseof V then V end

USER_HOME       = case {Getenv 'HOME'} of false then
                     {{`Builtin` 'OS.getCWD' 1}}
                  elseof V then V end

%{SET 'os.name'         OS_NAME         }
%{SET 'os.cpu'          OS_CPU          }
{SET 'path.separator'   PATH_SEPARATOR  }
{SET 'path.escape'      PATH_ESCAPE     }
%{SET 'oz.home'         OZ_HOME         }
{SET 'oz.search.path'   OZ_SEARCH_PATH  }
{SET 'oz.search.load'   OZ_SEARCH_LOAD  }
{SET 'oz.search.dload'  OZ_SEARCH_DLOAD }
{SET 'user.home'        USER_HOME       }