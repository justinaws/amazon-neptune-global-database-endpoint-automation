# Automated endpoint management for Amazon Neptune Global Database
This solution includes a cloudformation template and a python script. This document will describe how to use this solution.

# Architecture

![Architecture](https://github.com/justinaws/amazon-neptune-global-database-endpoint-automation/assets/147440980/70dcb257-2956-4317-9a83-4080dab0061e)

# Requirements
AWS CLI already configured with Administrator permission
Latest version of Python 3
AWS SDK for Python (boto3)
AWS Account with at least one Amazon Aurora Global Database with at least 2 regions.
Git command line tools installed
# Set up
Follow the instructions below in order to deploy from this repository:
1. Clone the repo onto your local development machine:
   git clone https://github.com/justinaws/amazon-neptune-global-database-endpoint-automation.git
2. In the root directory, from the command line, run following command. Please make sure you pass all regions where your global database clusters are deployed. This command will execute the cloudformation template and create all required resources in all passed regions.
   ```
   usage:
    python buildstack.py [--template-body <'managed-gdb-cft.yml'>] <--stack-name 'stackname'>  [--consent-anonymous-data-collect <'yes/no'>] <--region-list 'regionlist'>

   example:
    python3 buildstack.py --template-body 'managed-gdb-cft.yml' --stack-name 'gdb-managed-ep'  --consent-anonymous-data-collect 'yes' --region-list 'us-east-1,us-west-1'
   ```
3. Once the cloudformation finishes building resources in all regions, execute the following command, passing all regions of the global databases you wish to manage.

   ```
   usage
   python create_managed_endpoint.py --cluster-cname-pair='{"<global database clustername>":"<desired writer endpoint >"} [,"<global database clustername>":"<desired writer endpoint>"},...]' --hosted-zone-name=<hosted zone name> --region-list <'regionlist'>

   example:
   python create_managed_endpoint.py --cluster-cname-pair='{"gdb-cluster1":"writer1.myhostedzone.com" ,"gdb-cluster2":"writer2.myhostedzone.com"}' --hosted-zone-name=myhostedzone.com --region-list 'us-east-1,us-west-1'
   ```
# What resources will this solution create?
1. Global resources:
   Private Hosted Zone (Route 53): A private hosted Zone will be created based on the values you passed.
   CNAME: A CNAME will be created inside the hosted zone based on the parameters you passed.
2. Local resources created per region:
   IAM Role: An IAM role will be created so the Lambda function can assume this role while executing.
   Lambda function: This is the workhorse of the solution. This lambda will be fired on global database failover completion event, and will update the cname.
   DynamoDB table: A DynamoDB table named gdbcnamepair will be created. This table keeps track of the clusters that will be managed by this solution.
   EventBridge Rule: This EventBridge Rule will be fired when a global database completes failover in the region. This rule has the Lambda function as it's target.

# Cleanup 

  To remove this solution from your account, do following:

     1. Delete the cloudformation stack from all regions.
     2. Delete the CNAME record entries from the private hosted zone.
     3. Delete the private hosted zone.

# Current Limitations
  Partial SSL Support - Since the solution uses a Route 53 CNAME, the SSL certificate will not be able to validate the aurora servername. For example pgsql client verify-full or mysql client ssl-verify-server-cert will fail to validate server identity.
