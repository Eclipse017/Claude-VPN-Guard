const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('book',{status:()=>ipcRenderer.invoke('book:status'),action:a=>ipcRenderer.invoke('book:action',a)});
