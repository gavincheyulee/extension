import os.path
import os
import shutil
 
path="/Users/suhanjiang/Desktop/txt2dat"
#/Users/suhanjiang/Desktop/txt2dat/src
def txt2dat(fp,file):
    if os.path.exists(fp):
        print "processing",fp
        ftxt=open(fp,'r')
        dataname=str(fp[:-4])+".dat"
        fdat=open(dataname,'w')
        for l in ftxt.readlines():
            if l[0] == '#':
                pass
            else: 
                fdat.write(l)
                fdat.flush
        fdat.close()  
        ftxt.close() 
        newpath=dataname.replace('src','dst')
        shutil.move(dataname, newpath)   
       # wb.save(path+"/dst"+/str(file[:-4])+'.dat')           
    
 
 
def getfiles():
    files=os.listdir(path+"/src")
    for file in files:
        fp = path+"/src/"+file
        txt2dat(fp,file)
 
if __name__=='__main__':
    getfiles()
    print "done, press enter to stop."
    raw_input()


