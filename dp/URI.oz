%%%
%%% Author:
%%%   Denys Duchier <duchier@ps.uni-sb.de>
%%%   Christian Schulte <schulte@dfki.de>
%%%
%%% Copyright:
%%%   Denys Duchier, 1998
%%%   Christian Schulte, 1998
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

%%% ==================================================================
%%%                           URI LIBRARY
%%% ==================================================================
%%%
%%% This library provides utilities for the manipulation of URIs
%%% (Uniform Resource Identifiers) and filenames.  It supports both
%%% Unix and Windows syntax where they do not conflict.  There are no
%%% plans to ever support VMS's strange filename syntax.
%%%
%%% HISTORY
%%%
%%% The first implementation of such a library was written by
%%% Christian Schulte for his Module Manager.  It has been entirely
%%% rewritten by Denys Duchier to add various extensions such as
%%% support for Windows-style filenames.  The new implementation also
%%% improves the theoretical complexity, although not necessarily the
%%% performance.
%%%
%%% What is definitely improved is the correctness: the library now
%%% fully conforms to URI syntax as defined in IETF draft "Uniform
%%% Resource Identifiers (URI): Generic Syntax" by T. Berners- Lee,
%%% R. Fielding, and L. Masinter, of June 4, 1998, available at
%%% http://search.ietf.org/internet-drafts/draft-fielding-uri-syntax-03.txt
%%% and passes all 5 test suites published by Roy Fielding.
%%%
%%% The only derogations to said specification are made to accommodate
%%% Windows-style filenames: (1) a prefix of the form "C:" where C is
%%% a single character is interpreted as Windows-style device notation
%%% rather than as a uri scheme - in practice, this is a compatible
%%% extension as there are no legal single character schemes, (2) path
%%% segments may indifferently be separated by "/" or "\" - this too
%%% is compatible since non-separator forward and back slashes ought
%%% to be otherwise `escape encoded'.
%%%
%%% Actually, there is currently a further experimental extension: all
%%% uris may be suffixed by a string of the form "{foo=a,bar=b}".  This
%%% adds add an info record to the parsed representation of the uri:
%%% this record is info(foo:a bar:b).  Eventually this should probably
%%% be replaced by a notational facility to attach properties to imports
%%%
%%% INTERFACE
%%%
%%% {URI.make LOC}
%%%
%%%     parses LOC according to the proposed URI syntax modulo
%%% Windows-motivated derogation (see above).  Local filename syntax
%%% is a special case of schemeless uri.  The parsed representation of
%%% a uri is a chunk whose features hold the various parts of the uri.
%%%
%%% {URI.is X}
%%%
%%%     returns true iff X is the parsed representation of a uri, i.e.
%%% if it is a chunk with the private feature that identifies uris.
%%% this cannot be forged.
%%%
%%% {URI.resolve BASE REL}
%%%
%%%     BASE and REL are parsed uris.  REL is resolved relative to BASE
%%% and a new parsed uri is returned with the appropriate bits filled
%%% in.
%%%
%%% {URI.toString X}
%%%
%%%     X may be a string or a uri.  The corresponding normalized string
%%% representation is returned.  This simply looks up the string feature
%%% of the uri which is computed ByNeed.
%%%
%%% {URI.toAtom X}
%%%
%%%     Same as above, but an atom is returned instead.  This not
%%% further optimized: the atom is computed each time from the string
%%% feature.
%%%
%%% {URI.expand U}
%%%
%%%     U is a parsed URI.  If it is a relative uri, it is transformed
%%% into an absolute uri as follows: if it begins with "~" then the
%%% appropriate user home directory is pluged instead, else the current
%%% directory is prepended.
%%%
%%% BUGS AND LIMITATIONS
%%%
%%% Currently, parameters remain attached to their path component.
%%% This maybe insufficient when an application needs access to these
%%% parameters.
%%%
%%% The draft standard is ambiguous: in a relative uri, the leading
%%% segment is allowed to contain occurrences of ";".  Is the parameter
%%% parsing semantics as usual or not?  This is not clear and I should
%%% ask Roy Fielding for a clarification.
%%% ==================================================================

declare
local
   %% -- needed builtins and other functions
   \insert init-defs.oz

   %% -- a URI instance is an opaque chunk with feature URI_

   URI_ = {NewName}

   fun {URI_is X}
      {IsChunk X} andthen {HasFeature X URI_}
   end

   %% -- split a string at the first occurrence of a separator character,
   %% -- return the 2 halves as Prefix and Suffix and the separator
   %% -- character itself as Sep. Separator characters are specified
   %% -- using a bit array passed as argument Charset.

   proc {Split S Charset Prefix Suffix Sep}
      case S of nil then Prefix=Suffix=nil Sep=unit
      [] H|T then
         case {BitArrayTest Charset H} then
            Sep=H Prefix=nil Suffix=T
         else More in
            Prefix = H|More
            {Split T Charset More Suffix Sep}
         end
      end
   end

   %% -- create various bit arrays to serve as Charset argument to
   %% -- Split.  Each corresponds to a particular state of the uri
   %% -- parser as progress is being made through the input uri.

   local
      proc {Make L Charset}
         {BitArray.new 0 255 Charset}
         {ForAll L proc {$ C} {BitArray.set Charset C} end}
      end
   in
      CS1 = {Make  "/\\:?#{"}
      CS2 = {Make   "/\\?#{"}
      CS5 = {Make       "#{"}
      CS6 = {Make        "{"}
   end

   %% -- accumulate data S under feature F in dictionary D.
   %% -- feature F=path is treated specially: it should be a queue
   %% -- to optimize incremental accumulation of path components
   %% -- at the end. feature F=start indicates that this is the
   %% -- first thing to be accumulated: we have found no scheme,
   %% -- no device, and no authority. what we are recording is
   %% -- really the first path component, which happens to appear
   %% -- at the front of the uri.

   proc {Accu D F S}
      case F
      of path then C=dir({Decode S}) in
         case {Dictionary.condGet D path unit} of H#T
         then L in T=C|L {Dictionary.put D path     H#L}
         else L in       {Dictionary.put D path (C|L)#L} end
      [] file then
         case S of nil then skip else C=file({Decode S}) in
            case {Dictionary.condGet D path unit} of H#T
            then L in T=C|L {Dictionary.put D path     H#L}
            else L in       {Dictionary.put D path (C|L)#L} end
         end
      [] start then
         case S of nil then skip else L in
            {Dictionary.put D path (file({Decode S})|L)#L}
         end
      else
         {Dictionary.put D F S}
      end
   end

   %% -- Christian's original parser used String.token repeatedly and
   %% -- thus ended up traversing and copying the string several times.
   %% -- This new parser traverses the string only once and uses
   %% -- Charsets represented as bit arrays to recognize crucial
   %% -- characters that determine the breaking points in a uri.  On
   %% -- test data such as 'http://www.ps.uni.sb.de/ozhome/GetArgs.ozf'
   %% -- the new parser achieves a speedup of about 1.2 (with respect
   %% -- to Christian's parser slowed down by my extensions e.g. for
   %% -- Windows).  This new parser is also more robust; for example
   %% -- it correctly parses //foo:66/bar.

   %% -- The parser is a state machine, with 5 states:
   %% --
   %% -- START          is the initial state, what is at the front of
   %% --                the uri is disambiguated by the first separator
   %% --                we find or the eos.
   %% -- AUTHORITY      is when we have encountered the // thing.
   %% -- PATH           is the main state, when we are expecting a path
   %% --                component (segment).
   %% -- QUERY          is after "?"
   %% -- FRAGMENT       is after "#"
   %%
   %% -- when recording a path component we must distinguish whether
   %% -- it was followed by a "/" or not.  Kind==path normally implies
   %% -- that a "/" was found, because this is the most frequent case.
   %% -- when we hit the eos we must check whether we are currently in
   %% -- state 'path', in which case we record the path component using
   %% -- key 'file' instead to indicate that a "/" was not found. Also,
   %% -- when we find a "/", we must check whether we where in the start
   %% -- state, if yes, we have just found a path component.  If we hit
   %% -- one of "?#{" in the path state, then we have accumulated a
   %% -- non-directory path component: we indicate this to the
   %% -- accumulator using feature=file.  When the accumulator is handed
   %% -- feature=start, this means that we have hit one of "?#{" while
   %% -- in the start state: if the value to be accumulated is nil, then
   %% -- there really was nothing to accumulate, else it is a non
   %% -- directory path component.

   fun {URI_make LOC}
      case {URI_is LOC} then LOC else

         %% -- accumulate components of uri in Data
         Data = {Dictionary.new}

         %% -- Loop is the workhorse.  L is what remains of the input
         %% -- uri string, Charset is a bit array specifying which
         %% -- separators we are looking for.  Kind is an atom indicating
         %% -- what kind of component we are now expecting at the front
         %% -- of L.

         proc {Loop L Charset Kind}
            Prefix Suffix Sep
         in
            {Split L Charset Prefix Suffix Sep}
            case Sep
            of unit then
               %% -- we hit the end without finding a separator
               {Accu Data case Kind==path orelse Kind==start
                          then file else Kind end Prefix}
            [] &: then
               %% -- we found the scheme or device separator
               case Prefix of [C] then L in
                  %% -- it is a device: downcase it
                  {Accu Data device [{CharToLower C}]}
                  %% -- is the path absolute or relative
                  case Suffix of H|T then
                     case H==&/ orelse H==&\\ then
                        %% -- absolute
                        {Accu Data absolute true}
                        L = T
                     else
                        %% -- relative
                        {Accu Data absolute false}
                        L = Suffix
                     end
                     {Loop L CS2 path}
                  else skip end
               else
                  %% -- it is a scheme: downcase it
                  {Accu Data scheme {Map Prefix CharToLower}}
                  %% -- check for //authority
                  case Suffix of H1|T1 then
                     case H1==&/ then
                        %% -- in any case now, the path is absolute
                        {Accu Data absolute true}
                        case T1 of H2|T2 then
                           case H2==&/ then
                              %% -- found //, expect authority
                              {Loop T2 CS2 authority}
                           else
                              %% -- just an absolute path
                              {Loop T1 CS2 path}
                           end
                        else skip end
                     elsecase H1==&\\ then
                        %% -- Windows style absolute path
                        {Accu Data absolute true}
                        {Loop T1 CS2 path}
                     else
                        %% -- relative path
                        {Accu Data absolute false}
                        {Loop Suffix CS2 path}
                     end
                  else skip end
               end
            [] &/ then
               %% -- a Unix path separator
               case Kind==start then
                  %% -- this is our first stop
                  case Prefix of nil then
                     %% -- the slash is the 1st character
                     {Accu Data absolute true}
                     case Suffix of &/|L then
                        {Loop L CS2 authority}
                     else
                        {Loop Suffix Charset path}
                     end
                  else
                     %% -- Prefix is 1st relative path component
                     {Accu Data absolute false}
                     {Accu Data path Prefix}
                     {Loop Suffix Charset path}
                  end
               else
                  {Accu Data Kind Prefix}
                  {Loop Suffix Charset path}
               end
            [] &\\ then
               %% -- a Windows path separator
               case Kind==start then
                  %% -- this is our first stop
                  case Prefix of nil then
                     %% -- the backslash is the 1st character
                     {Accu Data absolute true}
                  else
                     %% -- Prefix is 1st relative path component
                     {Accu Data absolute false}
                     {Accu Data path Prefix}
                  end
               else
                  {Accu Data Kind Prefix}
               end
               {Loop Suffix Charset path}
            [] &? then
               %% -- query starts here
               {Accu Data case Kind==path then file else Kind end Prefix}
               {Loop Suffix CS5 query}
            [] &# then
               %% -- fragment starts here
               {Accu Data case Kind==path then file else Kind end Prefix}
               {Loop Suffix CS6 fragment}
            [] &{ then
               %% -- experimental info starts here
               {Accu Data case Kind==path then file else Kind end Prefix}
               {Accu Data info Suffix}
            end
         end

         %% -- parse LOC
         {Loop {VSToString LOC} CS1 start}

         %% -- post-process accumulated data
         %% -- info is still unparsed: turn it into a record
         I = {Dictionary.condGet Data info unit}
         case I of unit then skip else
            {Dictionary.put Data info {URL_info I}}
         end
         %% -- absolute indicator should be put as label on path
         A = {Dictionary.condGet Data absolute unit} ABS
         case A of unit then ABS=rel else
            {Dictionary.remove Data absolute}
            ABS = case A then abs else rel end
         end
         %% -- path was queue: turn it into a list and normalize
         P = {Dictionary.condGet Data path unit}
         case P of H#T then
            T=nil {Dictionary.put Data path ABS({Normalize H nil})}
         else skip end
         %% -- authority must be downcased
         N = {Dictionary.condGet Data authority unit}
         case N of unit then skip else
            {Dictionary.put Data authority {Map N CharToLower}}
         end
      in
         {URI_fromDict Data}
      end
   end

   fun {LazyString U}
      {ByNeed fun {$} {VSToString {URI_toVS U}} end}
   end

   proc {URI_fromDict D U}
      REC
      %% -- add the normalized string (to be computed on demand)
      {Dictionary.put D string {LazyString U}}
      %% -- add the record representation itself then compute it
      {Dictionary.put D URI_ REC}
      {Dictionary.toRecord uri D REC}
   in
      {NewChunk REC U}
   end

   proc {URI_fromRec R U}
      %% -- add the normalized string (to be computed on demand)
      %% -- and the record representation
      REC = {Adjoin REC uri(string:{LazyString U} URI_:REC)}
   in
      {NewChunk REC U}
   end

   %% -- unoptimized parser for experimental info in uri.
   %% -- at the end of a uri we allow things like "{foo=a,baz=b}".
   %% -- When URL_info is called, the leading "{" has already been
   %% -- stripped and "foo=a,baz=b}" is transformed into the
   %% -- record info(foo:a baz:b).

   local
      %% -- remove trailing "}"
      fun {DO1 L}
         case L of H|T then
            case H==&} then
               case T==nil then nil end
            else H | {DO1 T} end
         end
      end
      %% -- from ATTRIB=VALUE create the pair of atoms ATTRIB#VALUE
      fun {DO2 S} S1 S2 in
         {StringToken S &= S1 S2}
         {StringToAtom S1}#{StringToAtom S2}
      end
   in
      fun {URL_info STR}
         %% -- remove trailing "}", split at ",", convert to list
         %% -- of ATTRIB#VALUE, convert to record
         {ListToRecord info {Map {StringTokens {DO1 STR} &,} DO2}}
      end
   end

   %% -- normalizing a path represented by a sequence of dir(S) and
   %% -- file(S), where S is a string, is the process of eliminating
   %% -- occurrences of path components "." and ".." by interpreting
   %% -- them relative to the stack of path components.  This algorithm
   %% -- is due to Christian.  I modified it to handle labeled strings.

   fun {Normalize Path Stack}
      case Path of nil then {Reverse Stack}
      [] Head|Tail then
         case Head.1 of &.|T then
            case T of nil then {Normalize Tail Stack}
            [] "." then
               case Stack of Top|Stack then {Normalize Tail Stack}
               else Head | {Normalize Tail nil} end
            else {Normalize Tail Head|Stack} end
         else {Normalize Tail Head|Stack} end
      end
   end

   %% -- for truly normalizing a uri, we need to decode its components
   %% -- Decode applies decoding to the string of a single component

   local
      D = x(&0:0 &1:1 &2:2 &3:3 &4:4 &5:5 &6:6 &7:7 &8:8 &9:9
            &a:10 &b:11 &c:12 &d:13 &e:14 &f:15
            &A:10 &B:11 &C:12 &D:13 &E:14 &F:15)
   in
      fun {Decode L}
         case L of nil then nil
         [] H|T then
            case H==&% then
               case T of X1|X2|T then
                  (D.X1*16)+D.X2 | {Decode T}
               else H | {Decode T} end
            else H | {Decode T} end
         end
      end
   end

   %% -- for producing really normalized uri strings, we need to encode
   %% -- its components.  Encode applies encoding to the string of a
   %% -- single component and uses a bit array to recognize the characters
   %% -- that don't need to be escape-encoded.

   local
      D = x(0:&0 1:&1 2:&2 3:&3 4:&4 5:&5 6:&6 7:&7 8:&8 9:&9
            10:&a 11:&b 12:&c 13:&d 14:&e 15:&f)
   in
      fun {Encode L Charset}
         case L of nil then nil
         [] H|T then
            case {BitArrayTest Charset H} then
               H            | {Encode T Charset}
            else
               X1 = H div 16
               X2 = H mod 16
            in
               &% | D.X1 | D.X2 | {Encode T Charset}
            end
         end
      end
   end

   %% -- here a charset for encoding path segments
   %% -- BUG: ";" should not be in there but for the moment since I am
   %% -- not parsing parameters but leave them with the path component
   %% -- it needs to _not_ be encoded, but left.

   CSOK = {BitArray.new 0 255}
   {ForAll
    ";abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'():@&=+$,"
    proc {$ C} {BitArray.set CSOK C} end}

   %% -- converting a uri record to a virtual string

   fun {URI_toVS U}
      Scheme    = {CondSelect U scheme    unit}
      Device    = {CondSelect U device    unit}
      Authority = {CondSelect U authority unit}
      Path      = {CondSelect U path      unit}
      Query     = {CondSelect U query     unit}
      Fragment  = {CondSelect U fragment  unit}
      Info      = {CondSelect U info      unit}
      S1 = case Info==unit then nil else
              '{'#{RecordFoldRInd Info
                   fun {$ F V L}
                      case V=='' then F else F#'='#V end
                      #case L==unit then '}' else ' '#L end
                   end unit}
           end
      S2 = case Fragment ==unit then S1 else "#"#Fragment #S1 end
      S3 = case Query    ==unit then S2 else '?'#Query    #S2 end
      S4 = S3
      S5 = case Path of unit then S4 else
              L = {FoldR Path.1
                   fun {$ C L}
                      case C.1==nil then '' else {Encode C.1 CSOK} end
                      # case {Label C}==dir then '/'#L else L end
                   end nil}#S4
           in case {Label Path}==abs then '/'#L else L end end
      S6 = case Device==unit then S5 else Device#':'#Path end
      S7 = case Authority==unit then S6 else
              '//'#Authority#
              case S6==nil orelse
                 (Device==unit andthen
                  {IsRecord Path} andthen {Label Path}==abs)
              then S6 else '/'#S6 end
           end
      S8 = case Scheme==unit then S7 else Scheme#':'#S7 end
   in
      S8
   end

   %% -- resolving en Relative uri with respect to a Base uri.

   fun {URI_resolve Base Rel}
      %% -- maybe should optimize the case when one of them is empty
      case {HasFeature Rel scheme} then Rel
      else D = {Record.toDictionary Rel.URI_} in
         try
            %% -- Scheme
            Scheme = {CondSelect Base scheme unit}
            case Scheme==unit then skip else
               {Dictionary.put D scheme Scheme}
            end
            %% -- Authority
            case {Dictionary.member D authority}
            then raise done end else skip end
            Authority = {CondSelect Base authority unit}
            case Authority==unit then skip else
               {Dictionary.put D authority Authority}
            end
            %% -- Device
            case {Dictionary.member D device}
            then raise done end else skip end
            Device = {CondSelect Base device unit}
            case Device==unit then skip else
               {Dictionary.put D device Device}
            end
            %% -- Path
            Path = {CondSelect Base path unit}
            case Path==unit then raise done end else skip end
            A = {Label Path}
            case {Dictionary.condGet D path unit}
            of unit then
               %% -- no path in Rel
               {Dictionary.put D path A({AtLast Path.1 [file(nil)]})}
            elseof rel(L) then
               %% -- relative path in Rel
               {Dictionary.put D path
                A({Normalize {AtLast Path.1
                              case L of nil then [file(nil)]
                              %% elseof [".."] then [".." nil]
                              else L end}
                   nil})}
            else skip end
         in skip catch done then skip end
         {URI_fromDict D}
      end
   end

   fun {AtLast L1 L2}
      case L1 of nil then L2
      [] H1|T1 then
         case T1 of nil then L2
         %% elseof [nil] then L2
         else H1 | {AtLast T1 L2} end
      end
   end

   fun {URI_toString U} U.string end
   fun {URI_toAtom   U} {VSToAtom U.string} end

   %% -- TILDE and DOT NORMALIZATION -- when "~" or "." appear at the
   %% -- front of a local relative filename, they can be expanded with
   %% -- respectively a user home directory or the current directory.
   %% -- However, "." never apears at the front of a path because it
   %% -- has been normalized away: it is implicit in all relative paths
   %% -- that do not begin with "~...".

   fun {URI_expand U}
      case
         {CondSelect U scheme    unit}==unit andthen
         {CondSelect U authority unit}==unit andthen
         {CondSelect U device    unit}==unit
      then
         try
            case {CondSelect U path unit}
            of rel(dir(&~|USER)|_) then
               {URL_front true
                case USER==nil then {GET 'user.home'}
                else {Getpwnam USER}.dir end U}
            elseof rel(_) then
               {URL_front false {GetCWD} U}
            else U end
         catch _ then U end
      else U end
   end

   %% -- if Skip1 is true, remove 1st segment of relative path in Rel.
   %% -- prepend parsed Path. return new parsed uri. Skip1==true is
   %% -- used to drop a leading ~USER component in the relative uri
   %% -- parsed as Rel.

   fun {URL_front Skip1 Path Rel}
      %% -- oh hum! we need to add a trailing slash so that the Path
      %% -- end with a directory component rather than a file
      %% -- component.  This should be enforced by normalization.
      Front = {URI_make Path#'/'}.path.1
      Back= case Skip1 then Rel.path.(1).2 else Rel.path.1 end
      Abs = {Normalize {Append Front Back} nil}
   in
      {URI_fromRec {AdjoinAt Rel path abs(Abs)}}
   end

in
   URI = uri(is         : URI_is
             make       : URI_make
             resolve    : URI_resolve
             toString   : URI_toString
             toAtom     : URI_toAtom
             expand     : URI_expand)
end