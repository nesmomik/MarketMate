# Using AWS IAM Identity Center (SSO) with the AWS CLI

 ## 1. Enable AWS IAM Identity Center

1. Navigate to the IAM Identity Center in the AWS Web Console
2. Enable an account instance of the IAM Identity Center

## 2. Create a Permission Set

A **permission set** defines the permissions that will be granted when accessing AWS through SSO.

Steps:

1. Open **IAM Identity Center** in the AWS Console.
2. Navigate to **Permission sets**.
3. Click **Create permission set**.
4. Choose a predefined policy (for example `AdministratorAccess` for learning purposes).

When assigned to an account, AWS automatically creates a corresponding **IAM role**.

## 3. Assign the Permission Set to Your User

Next, assign your user access to your AWS account using the permission set.

Steps:

1. Go to **IAM Identity Center → AWS accounts**.
2. Select your AWS account.
3. Click **Assign users or groups**.
4. Select your user.
5. Select the permission set created earlier.

AWS will create a role similar to: AWSReservedSSO_AdministratorAccess_<random>

## 4. Retrieve the SSO Start URL

The **SSO start URL** is required for CLI configuration.

Steps:

1. Open **IAM Identity Center → Settings**.
2. Copy the **AWS access portal URL**.

Example: https://<directory-id>.awsapps.com/start

## 4. Configure AWS CLI for SSO

Run the following command:

`aws configure sso`

You will be prompted for:

```
SSO session name
SSO start URL
SSO region
```

Example:
```
SSO start URL: https://d-123456.awsapps.com/start
SSO region: eu-central-1
```

The CLI will open a browser for authentication and allow you to select:
- the AWS account
- the role (permission set)

You will then choose a profile name (for example sso-admin).

## 6. Log in with AWS SSO

Authenticate using:

`aws sso login --profile sso-admin`

This command:
- Opens a browser.
- Authenticates you via IAM Identity Center.
- Stores a temporary authentication token locally.

Token cache location:

~/.aws/sso/cache/

## 6. Use the CLI Profile

You can now run AWS CLI commands using the SSO profile:

`aws s3 ls --profile sso-admin`

Or set the profile as default for the session:

`export AWS_PROFILE=sso-admin`

The CLI will automatically obtain temporary credentials for the assigned role when executing commands.