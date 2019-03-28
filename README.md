# ClickFabric - Add Organization #

So this script let's you to add user to your existing running Hyperledger Fabric just by running a single script( Will soon be coming with a UI for the same, if possible :D ). This script is meant for developers and is only useful when the project is in development phase.

Directions to Use:
1) Clone this repo.
2) Paste it's contents into the current directory.

And then you are good to go.

Just use the add.sh script for now (as there is no UI). Try the -h flag to see what all can be done,

> ./add.sh -h.

Although the -o and -p flags are necessary to be passed, an example would be,

> ./add.sh -o "org1" -p "peer0"


My idea is to create a specific organization which acts like a network manager and is able to add other organizations to the network without requiring signatures from all the organizations in the existing network (or to be specific, channel). And name that organization as the Network Admin, although as of now I have not been able to achieve this and signatures from all the Organization's Admin are required. 

But still right now you are forced to pass your chosen Network Admin. Otherwise you won't be able to proceed.  

## Limitations: ##

1) You need to have an already created network first.
2) All the fabric binaries must be present in bin folder in your current project directory.
3) The MSP's default configuration is set with the following properties:

     a) MSPID="OrdererMSP"   

     b) Host Name is example.com

    > **Solution:**
    
        You can change this config in the setOrdererGlobals Method.
3) This will only work if your Linux Distribution supports snap packages.

    > **Solution:**

        If you want to use apt you can uncomment the lines 54-56 in step1neworg.sh

4) It is mandatory to have a scripts folder which should also be binded with the CLI container. And you should not have a folder with the name of newOrgscripts in your existing project.

5) We have yet not used service discovery, this is stopping us to let the entire network know about the new member being added.



