% This file is part of OpenModelica.
% Copyright (c) 1998-CurrentYear, Open Source Modelica Consortium (OSMC),
% c/o Link�pings universitet, Department of Computer and Information Science,
% SE-58183 Link�ping, Sweden.
%
% All rights reserved.
%
% THIS PROGRAM IS PROVIDED UNDER THE TERMS OF THE BSD NEW LICENSE OR THE
% GPL VERSION 3 LICENSE OR THE OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
% ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
% RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
% ACCORDING TO RECIPIENTS CHOICE.
%
% The OpenModelica software and the OSMC (Open Source Modelica Consortium)
% Public License (OSMC-PL) are obtained from OSMC, either from the above
% address, from the URLs: http://www.openmodelica.org or
% http://www.ida.liu.se/projects/OpenModelica, and in the OpenModelica
% distribution. GNU version 3 is obtained from:
% http://www.gnu.org/copyleft/gpl.html. The New BSD License is obtained from:
% http://www.opensource.org/licenses/BSD-3-Clause.
%
% This program is distributed WITHOUT ANY WARRANTY; without even the implied
% warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE, EXCEPT AS
% EXPRESSLY SET FORTH IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE
% CONDITIONS OF OSMC-PL.

classdef OMMatlab < handle
    properties (Access = private)
        process
        context
        requester
        portfile
        filename
        modelname
        xmlfile
        resultfile=''
        csvfile=''
        mattempdir=''
        simulationoptions=struct
        quantitieslist=[]
        parameterlist=struct
        continuouslist=struct
        inputlist=struct
        outputlist=struct
        mappednames=struct
        overridevariables=struct
        simoptoverride=struct
        inputflag=false
        linearOptions=struct('startTime','0.0','stopTime','1.0','numberOfIntervals','500','stepSize','0.002','tolerance','1e-6')
        linearfile
        linearFlag=false
        linearmodelname
        linearinputs
        linearoutputs
        linearstates
        linearquantitylist
        %fileid
    end
    methods
        function obj = OMMatlab(omcpath)
            %randomstring = char(97 + floor(26 .* rand(10,1)))';
            [~,randomstring]=fileparts(tempname);
            startInfo = System.Diagnostics.ProcessStartInfo();
            startInfo.Arguments=['--interactive=zmq +z=matlab.',randomstring];
            startInfo.UseShellExecute=false;
            startInfo.CreateNoWindow=true;
            if ispc
                if ~exist('omcpath', 'var')
                    omhome = getenv('OPENMODELICAHOME');
                    omhomepath = replace(fullfile(omhome,'bin','omc.exe'),'\','/');
                    %add omhome to path environment variabel
                    %path1 = getenv('PATH');
                    %path1 = [path1 omhome];
                    %setenv('PATH', path1);
                    %cmd ="START /b "+omhomepath +" --interactive=zmq +z=matlab."+randomstring;
                    %cmd = ['START /b',' ',omhomepath,' --interactive=zmq +z=matlab.',randomstring];
                    startInfo.FileName=omhomepath;
                    startInfo.Environment.Add('OPENMODELICAHOME',omhome);
                else
                    [dirname1,~]=fileparts(fileparts(omcpath));
                    startInfo.FileName=omcpath;
                    startInfo.Environment.Add('OPENMODELICAHOME',dirname1);
                end
                portfile = strcat('openmodelica.port.matlab.',randomstring);
            else
                if ismac && system("which omc") ~= 0
                    %cmd =['/opt/openmodelica/bin/omc --interactive=zmq -z=matlab.',randomstring,' &'];
                    if ~exist('omcpath', 'var')
                        startInfo.FileName='/opt/openmodelica/bin/omc';
                    else
                        startInfo.FileName=omcpath;
                    end
                else
                    %cmd =['omc --interactive=zmq -z=matlab.',randomstring,' &'];
                    if ~exist('omcpath', 'var')
                        startInfo.FileName='omc';
                    else
                        startInfo.FileName=omcpath;
                    end
                end
                portfile = strcat('openmodelica.',getenv('USER'),'.port.matlab.',randomstring);
            end
            %system(cmd);
            obj.process = System.Diagnostics.Process.Start(startInfo);
            %disp(obj.process.Id)
            %pause(0.2);
            obj.portfile = replace(fullfile(tempdir,portfile),'\','/');
            while true
                pause(0.01);
                if(isfile(obj.portfile))
                    filedata=fileread(obj.portfile);
                    break;
                end
            end
            import org.zeromq.*
            obj.context=ZMQ.context(1);
            obj.requester =obj.context.socket(ZMQ.REQ);
            %obj.portfile=replace(fullfile(tempdir,portfile),'\','/');
            %obj.fileid=fileread(obj.portfile);
            obj.requester.connect(filedata);
        end
        
        
        function reply = sendExpression(obj,expr)
            if(~obj.process.HasExited)
                obj.requester.send(expr,0);
                data=obj.requester.recvStr(0);
                % Parse java string object and return in appropriate matlab
                % structure if possible, otherwise return as normal strings
                reply=parseExpression(obj,string(data));
            else
                disp("Process Exited, No connection with OMC. Create a new instance of OMMatlab session");
                return
            end
        end
        
        function ModelicaSystem(obj,filename,modelname,libraries)
            if (nargin < 2)
                error('Not enough arguments, filename and classname is required');
            end
            
            if ~exist(filename, 'file')
                msg=filename +" does not exist";
                error(msg);
                return;
            end
            filepath = replace(filename,'\','/');
            %disp(filepath);
            loadfilemsg=obj.sendExpression("loadFile( """+ filepath +""")");
            if (loadfilemsg=="false")
                disp(obj.sendExpression("getErrorString()"));
                return;
            end
            % check for libraries
            if exist('libraries', 'var')
                %disp("library given");
                for n=1:length(libraries)
                    %disp("loop libraries:" + libraries{n});
                    if(isfile(libraries{n}))
                        libmsg = obj.sendExpression("loadFile( """+ libraries{n} +""")");
                    else
                        libmsg = obj.sendExpression("loadModel("+ libraries{n} +")");
                    end
                    %disp(libmsg);
                    if (libmsg=="false")
                        disp(obj.sendExpression("getErrorString()"));
                        return;
                    end
                end
            else
                %disp("library not given");
            end
            obj.filename = filename;
            obj.modelname = modelname;
            %tmpdirname = char(97 + floor(26 .* rand(15,1)))';
            
            obj.mattempdir = replace(tempname,'\','/');
            %disp("tempdir" + obj.mattempdir)
            mkdir(obj.mattempdir);
            obj.sendExpression("cd("""+ obj.mattempdir +""")")
            BuildModelicaModel(obj)
        end
        
        function BuildModelicaModel(obj)
            buildModelResult=obj.sendExpression("buildModel("+ obj.modelname +")");
            %r2=split(erase(string(buildModelResult),["{","}",""""]),",");
            %disp(r2);
            if(isempty(buildModelResult(1)))
                disp(obj.sendExpression("getErrorString()"));
                return;
            end
            %xmlpath =strcat(obj.mattempdir,'\',r2{2});
            xmlpath=fullfile(obj.mattempdir,char(buildModelResult(2)));
            obj.xmlfile = replace(xmlpath,'\','/');
            xmlparse(obj);
        end
        
        function workdir = getWorkDirectory(obj)
            workdir = obj.mattempdir;
            return;
        end
        
        function xmlparse(obj)
            if isfile(obj.xmlfile)
                xDoc=xmlread(obj.xmlfile);
                % DefaultExperiment %
                allexperimentitems = xDoc.getElementsByTagName('DefaultExperiment');
                obj.simulationoptions.('startTime') = char(allexperimentitems.item(0).getAttribute('startTime'));
                obj.simulationoptions.('stopTime') = char(allexperimentitems.item(0).getAttribute('stopTime'));
                obj.simulationoptions.('stepSize') = char(allexperimentitems.item(0).getAttribute('stepSize'));
                obj.simulationoptions.('tolerance') = char(allexperimentitems.item(0).getAttribute('tolerance'));
                obj.simulationoptions.('solver') = char(allexperimentitems.item(0).getAttribute('solver'));
                
                % ScalarVariables %
                allvaritem = xDoc.getElementsByTagName('ScalarVariable');
                for k = 0:allvaritem.getLength-1
                    scalar=struct;
                    scalar.('name')=char(allvaritem.item(k).getAttribute('name'));
                    scalar.('changeable')=char(allvaritem.item(k).getAttribute('isValueChangeable'));
                    scalar.('description')=char(allvaritem.item(k).getAttribute('description'));
                    scalar.('variability')=char(allvaritem.item(k).getAttribute('variability'));
                    scalar.('causality') =char(allvaritem.item(k).getAttribute('causality'));
                    scalar.('alias')=char(allvaritem.item(k).getAttribute('alias'));
                    scalar.('aliasVariable')=char(allvaritem.item(k).getAttribute('aliasVariable'));
%                     obj.quantitieslist(k+1).('name')=name;
%                     obj.quantitieslist(k+1).('changeable')=changeable;
%                     obj.quantitieslist(k+1).('description')=description;
%                     obj.quantitieslist(k+1).('variability')=variability;
%                     obj.quantitieslist(k+1).('causality')=causality;
%                     obj.quantitieslist(k+1).('alias')=alias;
%                     obj.quantitieslist(k+1).('aliasVariable')=aliasVariable;
                    sub = allvaritem.item(k).getElementsByTagName('Real');
                    try
                        value = char(sub.item(0).getAttribute('start'));
                    catch
                        value = '';
                    end
                    scalar.('value')=value;
                    %obj.quantitieslist(k+1).('value') = value;
                    
                    % check for variability parameter and add to parameter list
                    if(obj.linearFlag==false)
                        name=scalar.('name');
                        value=scalar.('value');
                        if(strcmp(scalar.('variability'),'parameter'))
                            try
                                obj.parameterlist.(name) = value;
                            catch ME
                                createvalidnames(obj,name,value,"parameter");
                            end
                        end
                        % check for variability continuous and add to continuous list
                        if(strcmp(scalar.('variability'),'continuous'))
                            try
                                obj.continuouslist.(name) = value;
                            catch ME
                                createvalidnames(obj,name,value,"continuous");
                            end
                        end
                        
                        % check for causality input and add to input list
                        if(strcmp(scalar.('causality'),'input'))
                            try
                                obj.inputlist.(name) = value;
                            catch ME
                                createvalidnames(obj,name,value,"input");
                            end
                        end
                        % check for causality output and add to output list
                        if(strcmp(scalar.('causality'),'output'))
                            try
                                obj.outputlist.(name) = value;
                            catch ME
                                createvalidnames(obj,name,value,"output");
                            end
                        end
                    end
                    if(obj.linearFlag==true)
                        if(scalar.('alias')=="alias")
                            name=scalar.('name');
                            if (name(2) == 'x')
                                obj.linearstates=[obj.linearstates,name(4:end-1)];
                            end
                            if (name(2) == 'u')
                                obj.linearinputs=[obj.linearinputs,name(4:end-1)];
                            end
                            if (name(2) == 'y')
                                obj.linearoutputs=[obj.linearoutputs,name(4:end-1)];
                            end
                        end
                        obj.linearquantitylist=[obj.linearquantitylist,scalar];
                    else
                        obj.quantitieslist=[obj.quantitieslist,scalar];
                    end
                end
            else
                msg="xmlfile is not generated";
                error(msg);
                return;
            end
        end
        
        function result= getQuantities(obj,args)
            if exist('args', 'var')
                tmpresult=[];
                for n=1:length(args)
                    for q=1:length(obj.quantitieslist)
                        if(strcmp(obj.quantitieslist(q).name,args(n)))
                            tmpresult=[tmpresult;obj.quantitieslist(q)];
                        end
                    end
                end
                result=struct2table(tmpresult,'AsArray',true);
            else
                result=struct2table(obj.quantitieslist,'AsArray',true);
            end
            return;
        end
        
        function result= getLinearQuantities(obj,args)
            if exist('args', 'var')
                tmpresult=[];
                for n=1:length(args)
                    for q=1:length(obj.linearquantitylist)
                        if(strcmp(obj.linearquantitylist(q).name,args(n)))
                            tmpresult=[tmpresult;obj.linearquantitylist(q)];
                        end
                    end
                end
                result=struct2table(tmpresult,'AsArray',true);
            else
                result=struct2table(obj.linearquantitylist,'AsArray',true);
            end
            return;
        end
        
        function result = getParameters(obj,args)
            if exist('args', 'var')
                param=strings(1,length(args));
                for n=1:length(args)
                    param(n) = obj.parameterlist.(args(n));
                end
                result = param;
            else
                result = obj.parameterlist;
            end
            return;
        end
        
        function result = getInputs(obj,args)
            if exist('args', 'var')
                inputs=strings(1,length(args));
                for n=1:length(args)
                    inputs(n) = obj.inputlist.(args(n));
                end
                result = inputs;
            else
                result = obj.inputlist;
            end
            return;
        end
        
        function result = getOutputs(obj,args)
            if exist('args', 'var')
                outputs=strings(1,length(args));
                for n=1:length(args)
                    outputs(n) = obj.outputlist.(args(n));
                end
                result = outputs;
            else
                result = obj.outputlist;
            end
            return;
        end
        
        function result = getContinuous(obj,args)
            if exist('args', 'var')
                continuous=strings(1,length(args));
                for n=1:length(args)
                    continuous(n) = obj.continuouslist.(args(n));
                end
                result = continuous;
            else
                result = obj.continuouslist;
            end
            return;
        end
        
        function result = getSimulationOptions(obj,args)
            if exist('args', 'var')
                simoptions=strings(1,length(args));
                for n=1:length(args)
                    simoptions(n) = obj.simulationoptions.(args(n));
                end
                result = simoptions;
            else
                result = obj.simulationoptions;
            end
            return;
        end
        
        function result = getLinearizationOptions(obj,args)
            if exist('args', 'var')
                linoptions=strings(1,length(args));
                for n=1:length(args)
                    linoptions(n) = obj.linearOptions.(args(n));
                end
                result = linoptions;
            else
                result = obj.linearOptions;
            end
            return;
        end
        
        % Set Methods
        function setParameters(obj,args)
            if exist('args', 'var')
                for n=1:length(args)
                    val=replace(args(n)," ","");
                    value=split(val,"=");
                    if(isfield(obj.parameterlist,char(value(1))))
                        obj.parameterlist.(value(1))= value(2);
                        obj.overridevariables.(value(1))= value(2);
                    else
                        disp(value(1) + " is not a parameter");
                        return;
                    end
                end
            end
        end
        
        function setSimulationOptions(obj,args)
            if exist('args', 'var')
                for n=1:length(args)
                    val=replace(args(n)," ","");
                    value=split(val,"=");
                    if(isfield(obj.simulationoptions,char(value(1))))
                        obj.simulationoptions.(value(1))= value(2);
                        obj.simoptoverride.(value(1)) = value(2);
                        %obj.overridevariables.(value(1))= value(2);
                    else
                        disp(value(1) + " is not a Simulation Option");
                        return;
                    end
                end
            end
        end
        
        function setLinearizationOptions(obj,args)
            if exist('args', 'var')
                for n=1:length(args)
                    val=replace(args(n)," ","");
                    value=split(val,"=");
                    if(isfield(obj.linearOptions,char(value(1))))
                        obj.linearOptions.(value(1))= value(2);
                        obj.linearOptions.(value(1))= value(2);
                    else
                        disp(value(1) + " is not a Linearization Option");
                        return;
                    end
                end
            end
        end
        
        function setInputs(obj,args)
            if exist('args', 'var')
                for n=1:length(args)
                    val=replace(args(n)," ","");
                    value=split(val,"=");
                    if(isfield(obj.inputlist,char(value(1))))
                        obj.inputlist.(value(1))= value(2);
                        obj.inputflag=true;
                    else
                        disp(value(1) + " is not a Input");
                        return;
                    end
                end
            end
        end
        
        function createcsvData(obj)
            obj.csvfile = replace(fullfile(obj.mattempdir,[char(obj.modelname),'.csv']),'\','/');
            fileID = fopen(obj.csvfile,"w");
            %disp(strjoin(fieldnames(obj.inputlist),","));
            fprintf(fileID,['time,',strjoin(fieldnames(obj.inputlist),","),',end\n']);
            %csvdata = obj.inputlist;
            fields=fieldnames(obj.inputlist);
            %time=strings(1,length(csvdata));
            time=[];
            count=1;
            tmpcsvdata=struct;
            for i=1:length(fieldnames(obj.inputlist))
                %disp(fields(i));
                %disp(obj.inputlist.(fields{i}));
                %disp("loop"+ num2str(i))
                %disp(fields{i})
                var = obj.inputlist.(fields{i});
                if(isempty(var))
                    var="0";
                end
                s1 = eval(replace(replace(replace(replace(var,"[","{"),"]","}"),"(","{"),")","}"));
                tmpcsvdata.(char(fields(i))) = s1;
                %csvdata.()=s1;
                %disp(length(s1));
                if(length(s1)>1)
                    for j=1:length(s1)
                        t = s1(j);
                        %disp(t{1}{1});
                        %time(count)=t{1}{1};
                        time=[time,t{1}{1}];
                        count=count+1;
                    end
                end
            end
            %disp(tmpcsvdata)
            %disp(length(time))
            if(isempty(time))
                time=[str2double(obj.simulationoptions.('startTime')),str2double(obj.simulationoptions.('stopTime'))];
            end
            t1=struct2cell(tmpcsvdata);
            %disp(length(t1))
            sortedtime=sort(time);
            previousvalue=struct;
            for t=1:length(sortedtime)
                fprintf(fileID,[num2str(sortedtime(t)),',']);
                %fprintf(fileID,[char(sortedtime(t)),',']);
                listcount=1;
                for i=1:length(t1)
                    tmp1=t1{i};
                    if(iscell(tmp1))
                        %disp("length is :" + length(tmp1))
                        found=false;
                        for k=1:length(tmp1)
                            if(sortedtime(t)==tmp1{k}{1})
                                %disp(sortedtime(t)+ "=>" + tmp1{k}{1})
                                data=tmp1{k}{2};
                                %disp(sortedtime(t)+ "=>" + data)
                                fprintf(fileID,[num2str(data),',']);
                                %pfieldname=matlab.lang.makeValidName(string(listcount));
                                pfieldname="x"+string(listcount);
                                previousvalue.(pfieldname)=data;
                                tmp1(k)=[];
                                t1{i}=tmp1;
                                found=true;
                                break;
                            end
                        end
                        if(found==false)
                            %disp(previousvalue)
                            %disp(string(listcount))
                            tmpfieldname="x"+string(listcount);
                            %disp("false loop" + previousvalue.(tmpfieldname))
                            data=previousvalue.(tmpfieldname);
                            fprintf(fileID,[num2str(data),',']);
                        end
                    else
                        %disp("strings found" + t1{i})
                        %disp(class(t1{i}))
                        %fprintf(fileID,'%s',t1{i},',');
                        fprintf(fileID,[num2str(t1{i}),',']);
                    end
                    listcount=listcount+1;
                end
                fprintf(fileID,[num2str(0),'\n']);
                %disp(sortedtime(t) + "****************************")
            end
            fclose(fileID);
        end
        
        function simulate(obj,resultfile,simflags)
            if exist('resultfile', 'var')
                %disp(resultfile);
                if ~isempty(resultfile)
                    r=join([' -r=',char(resultfile)]);
                    obj.resultfile=replace(fullfile(obj.mattempdir,char(resultfile)),'\','/');
                else
                    r='';
                end
            else
                r='';
                obj.resultfile=replace(fullfile(obj.mattempdir,[char(obj.modelname),'_res.mat']),'\','/');
            end
            if exist('simflags', 'var')
                simflags=join([' ',char(simflags)]);
            else
                simflags='';
            end
            if(isfile(obj.xmlfile))
                if (ispc)
                    getexefile = replace(fullfile(obj.mattempdir,[char(obj.modelname),'.exe']),'\','/');
                    %disp(getexefile)
                else
                    getexefile = replace(fullfile(obj.mattempdir,char(obj.modelname)),'\','/');
                end
                curdir=pwd;
                if(isfile(getexefile))
                    cd(obj.mattempdir)
                    if(~isempty(fieldnames(obj.overridevariables)) || ~isempty(fieldnames(obj.simoptoverride)))
                        names = [fieldnames(obj.overridevariables); fieldnames(obj.simoptoverride)];
                        tmpstruct = cell2struct([struct2cell(obj.overridevariables); struct2cell(obj.simoptoverride)], names, 1);
                        fields=fieldnames(tmpstruct);
                        tmpoverride1=strings(1,length(fields));
                        for i=1:length(fields)
                            if (isfield(obj.mappednames,fields(i)))
                                name=obj.mappednames.(fields{i});
                            else
                                name=fields(i);
                            end
                            tmpoverride1(i)=name+"="+tmpstruct.(fields{i});
                        end
                        overridevar=[' -override=',char(strjoin(tmpoverride1,','))];
                    else
                        overridevar='';
                    end
                    
                    if(obj.inputflag==true)
                        obj.createcsvData()
                        csvinput=join([' -csvInput=',obj.csvfile]);
                    else
                        csvinput='';
                    end
                    
                    finalsimulationexe = [getexefile,overridevar,csvinput,r,simflags];
                    %disp(finalsimulationexe);
                    system(finalsimulationexe);
                    %obj.resultfile=replace(fullfile(obj.mattempdir,[char(obj.modelname),'_res.mat']),'\','/');
                else
                    disp("Model cannot be Simulated: executable not found")
                end
                cd(curdir)
                %disp(pwd)
            else
                disp("Model cannot be Simulated: xmlfile not found")
            end
            
        end
        
        function result = linearize(obj)
            linres=obj.sendExpression("setCommandLineOptions(""+generateSymbolicLinearization"")");
            %disp(linres);
            %disp(obj.modelname);
            if(linres=="false")
                disp("Linearization cannot be performed"+obj.sendExpression("getErrorString()"));
                return;
            end
            %linearize(SeborgCSTR.ModSeborgCSTRorg,startTime=0.0,stopTime=1.0,numberOfIntervals=500,stepSize=0.002,tolerance=1e-6,simflags="-csvInput=C:/Users/arupa54/AppData/Local/Temp/jl_59DA.tmp/SeborgCSTR.ModSeborgCSTRorg.csv -override=a=2.0")
            
            fields=fieldnames(obj.overridevariables);
            tmpoverride1=strings(1,length(fields));
            for i=1:length(fields)
                tmpoverride1(i)=fields(i)+"="+obj.overridevariables.(fields{i});
            end
            if(~isempty(tmpoverride1))
                tmpoverride2=[' -override=',char(strjoin(tmpoverride1,','))];
            else
                tmpoverride2="";
            end
            
            linfields=fieldnames(obj.linearOptions);
            tmpoverride1lin=strings(1,length(linfields));
            for i=1:length(linfields)
                tmpoverride1lin(i)=linfields(i)+"="+obj.linearOptions.(linfields{i});
            end
            overridelinear=char(strjoin(tmpoverride1lin,','));
            
            if(obj.inputflag==true)
                obj.createcsvData()
                csvinput=join(['-csvInput=',obj.csvfile]);
            else
                csvinput="";
            end
            linexpr=strcat('linearize(',obj.modelname,',',overridelinear,',','simflags=','"',csvinput,'  ',tmpoverride2,'")');
            %res=obj.sendExpression("linearize(" + obj.modelname + ")");
            res=obj.sendExpression(linexpr);
            obj.resultfile=res.("resultFile");
            obj.linearmodelname=strcat('linear_',obj.modelname);
            obj.linearfile=replace(fullfile(obj.mattempdir,[char(obj.linearmodelname),'.mo']),'\','/');
            if(isfile(obj.linearfile))
                loadmsg=obj.sendExpression("loadFile("""+ obj.linearfile + """)");
                if(loadmsg=="false")
                    disp(obj.sendExpression("getErrorString()"));
                    return;
                end
                cNames =obj.sendExpression("getClassNames()");
                buildmodelexpr=join(["buildModel(",cNames(1),")"]);
                buildModelmsg=obj.sendExpression(buildmodelexpr);
                %disp(buildModelmsg(:))
                if(~isempty(buildModelmsg(1)))
                    obj.linearFlag=true;
                    obj.xmlfile=replace(fullfile(obj.mattempdir,char(buildModelmsg(2))),'\','/');
                    obj.linearquantitylist=[];
                    obj.linearinputs=strings(0,0);
                    obj.linearoutputs=strings(0,0);
                    obj.linearstates=strings(0,0);
                    xmlparse(obj)
                    result=getLinearMatrix(obj);
                else
                    disp(omc.sendExpression("getErrorString()"));
                end
            end
            return;
        end
        
        function result = getLinearMatrix(obj)
            matrix_A=struct;
            matrix_B=struct;
            matrix_C=struct;
            matrix_D=struct;
            
            for i=1:length(obj.linearquantitylist)
                name=obj.linearquantitylist(i).("name");
                value= obj.linearquantitylist(i).("value");
                if( obj.linearquantitylist(i).("variability")=="parameter")
                    if(name(1)=='A')
                        tmpname=matlab.lang.makeValidName(name);
                        matrix_A.(tmpname)=value;
                    end
                    if(name(1)=='B')
                        tmpname=matlab.lang.makeValidName(name);
                        matrix_B.(tmpname)=value;
                    end
                    if(name(1)=='C')
                        tmpname=matlab.lang.makeValidName(name);
                        matrix_C.(tmpname)=value;
                    end
                    if(name(1)=='D')
                        tmpname=matlab.lang.makeValidName(name);
                        matrix_D.(tmpname)=value;
                    end
                end
            end
            FullLinearMatrix={};
            tmpMatrix_A=getLinearMatrixValues(obj,matrix_A);
            tmpMatrix_B=getLinearMatrixValues(obj,matrix_B);
            tmpMatrix_C=getLinearMatrixValues(obj,matrix_C);
            tmpMatrix_D=getLinearMatrixValues(obj,matrix_D);
            FullLinearMatrix{1}=tmpMatrix_A;
            FullLinearMatrix{2}=tmpMatrix_B;
            FullLinearMatrix{3}=tmpMatrix_C;
            FullLinearMatrix{4}=tmpMatrix_D;
            result=FullLinearMatrix;
            return;
        end
        
        function result = getLinearMatrixValues(~,matrix_name)
            if(~isempty(matrix_name))
                fields=fieldnames(matrix_name);
                t=fields{end};
                rows=str2double(t(3));
                columns=str2double(t(5));
                tmpMatrix=zeros(rows,columns,'double');
                for i=1:length(fields)
                    n=fields{i};
                    r=str2double(n(3));
                    c=str2double(n(5));
                    val=str2double(matrix_name.(fields{i}));
                    format shortG
                    tmpMatrix(r,c)=val;
                end
                result=tmpMatrix;
            else
                result=zeros(0,0);
            end
        end
        
        function result = getLinearInputs(obj)
            if(obj.linearFlag==true)
                result=obj.linearinputs;
            else
                disp("Model is not Linearized");
            end
            return;
        end
        
        function result = getLinearOutputs(obj)
            if(obj.linearFlag==true)
                result=obj.linearoutputs;
            else
                disp("Model is not Linearized");
            end
            return;
        end
        
        function result = getLinearStates(obj)
            if(obj.linearFlag==true)
                result=obj.linearstates;
            else
                disp("Model is not Linearized");
            end
            return;
        end
        
        function result = getSolutions(obj,args,resultfile)
            if exist('resultfile', 'var')
                resfile = char(resultfile);
            else
                resfile = obj.resultfile;
            end
            if(isfile(resfile))
                if exist('args', 'var') && ~isempty(args)
                    tmp1=strjoin(cellstr(args),',');
                    tmp2=['{',tmp1,'}'];
                    simresult=obj.sendExpression("readSimulationResult(""" + resfile + ""","+tmp2+")");
                    obj.sendExpression("closeSimulationResultFile()");
                    result=simresult;
                else
                    tmp1=obj.sendExpression("readSimulationResultVars(""" + resfile + """)");
                    obj.sendExpression("closeSimulationResultFile()");
                    result = tmp1;
                end
                return;
            else
                result= "Result File does not exist! " + char(resfile);
                disp(result);
                return;
            end
        end
        
        % function which creates valid field name as matlab
        % does not allow der(h) to be a valid name, also map
        % the changed names to mappednames struct, inorder to
        % keep track of the original names as it is needed to query
        % simulation results
        function createvalidnames(obj,name,value,structname)
            tmpname=matlab.lang.makeValidName(name);
            obj.mappednames.(tmpname)= name;
            if(strcmp(structname,'continuous'))
                obj.continuouslist.(tmpname)= value;
            end
            if(strcmp(structname,'parameter'))
                obj.parameterlist.(tmpname)= value;
            end
            if(strcmp(structname,'input'))
                obj.inputlist.(tmpname)= value;
            end
            if(strcmp(structname,'output'))
                obj.outputlist.(tmpname)= value;
            end
        end
        
        function result = parseExpression(obj,args)
            %final=regexp(args,'(?<=")[^"]+(?=")|[{}(),]|[a-zA-Z0-9.]+','match');
            final=regexp(args,'"(.*?)"|[{}()=]|[a-zA-Z0-9_.]+','match');
            %final=regexp(args,'"([^"]|\n)*"|[{}()=]|[a-zA-Z0-9.]+','match');
            if(length(final)>1)
                if(final(1)=="{" && final(2)~="{")
                    tmp3=strings(1,1);
                    count=1;
                    for i=1:length(final)
                        if(final(i)~="{" && final(i)~="}" && final(i)~="(" && final(i)~=")" && final(i)~=",")
                            value=replace(final{i},"""","");
                            tmp3(count)=value;
                            count=count+1;
                        end
                    end
                    result=tmp3;
                elseif(final(1)=="{" && final(2)=="{")
                    %result=eval(args);
                    tmpresults={1};
                    tmpcount=1;
                    count=1;
                    for i=2:length(final)-1
                        if(final(i)=="{")
                            if(isnan(str2double(final(i+1))))
                                tmp=strings(1,1);
                            else
                                tmp=[];
                            end
                        elseif(final(i)=="}")
                            tmpresults{tmpcount}=tmp;
                            tmp=[];
                            count=1;
                            tmpcount=tmpcount+1;
                        else
                            tmp(count)=final(i);
                            count=count+1;
                        end
                    end
                    result=tmpresults;
                elseif(final(1)=="record")
                    result=struct;
                    for i=3:length(final)-2
                        if(final(i)=="=")
                            value=replace(final(i+1),"""","");
                            result.(final(i-1))= value;
                        end
                    end
                elseif(final(1)=="fail")
                    result=obj.sendExpression("getErrorString()");
                else
                    %reply=final;
                    disp("returning unparsed string")
                    result=replace(args,"""","");
                    %result=args;
                end
            elseif(length(final)==1)
                result=replace(final,"""","");
            else
                disp("returning unparsed string")
                result=replace(args,"""","");
            end
        end
        
        function delete(obj)
            %disp("inside delete")
            delete(obj.portfile);
            obj.requester.close();
            % kill the spwaned process for omc
            obj.process.Kill()
            delete(obj);
        end
    end
end
