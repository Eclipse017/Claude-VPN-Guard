const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('setup',{call:(action,data)=>ipcRenderer.invoke('setup:call',action,data)});
