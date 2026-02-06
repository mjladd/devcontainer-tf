# TF Failure Troubleshooting

## Table of Contents

- [Step 0: clarify what kind of failure you're seeing](#first-clarify-what-kind-of-failure-youre-seeing)
- [Step 1: Turn Terraform into an API tracer (non-negotiable)](#step-1-turn-terraform-into-an-api-tracer-non-negotiable)
- [Step 2: Identify the failing AWS API call](#step-2-identify-the-failing-aws-api-call)
- [Step 3: Reproduce the failure with AWS CLI (critical skill)](#step-3-reproduce-the-failure-with-aws-cli-critical-skill)
- [Step 4: Use AWS CloudTrail as your ground truth](#step-4-use-aws-cloudtrail-as-your-ground-truth)
- [Step 5: Diff Terraform intent vs AWS requirements](#step-5-diff-terraform-intent-vs-aws-requirements)
- [Step 6: Use IAM simulation to prove missing permissions](#step-6-use-iam-simulation-to-prove-missing-permissions)
- [Step 7: Examine provider source code (advanced but powerful)](#step-7-examine-provider-source-code-advanced-but-powerful)
- [Step 8: Build a minimal repro outside the module](#step-8-build-a-minimal-repro-outside-the-module)
- [Step 9: Teach this debugging ladder explicitly](#step-9-teach-this-debugging-ladder-explicitly)
- [Final mindset shift (this is key)](#final-mindset-shift-this-is-key)

Let’s walk through a **very concrete, forensic workflow** you can teach for diagnosing *why a Terraform plan/apply fails*, and how to drop down to **AWS CLI + logs** to identify what the module is missing.

## Step 0: clarify what kind of failure you’re seeing

This matters because the tools differ.

**`terraform plan` fails**

Usually:

- invalid/missing arguments
- provider schema mismatch
- bad interpolation
- missing required inputs
- invalid values

This is likely a Terraform-side problem (no AWS API call yet)

**`terraform plan` succeeds, but `terraform apply` fails**

Usually:

- missing IAM permissions
- invalid AWS-side configuration
- dependency order issues
- eventual consistency
- service-specific constraints

This is likely an️ API-side problem (this is where AWS CLI & logs shine)

The rest of this answer assumes and API-side problem.

## Step 1: Turn Terraform into an API tracer (non-negotiable)

Before touching AWS CLI, capture *exactly* what Terraform tried to do.

```bash
TF_LOG=TRACE TF_LOG_PATH=terraform.log terraform apply
```

What this gives you:

- exact AWS API calls
- request parameters
- request IDs
- AWS error codes
- timestamps

**Key habit to teach:**

> Never debug blindly — always capture the request ID.

In `terraform.log`, search for:

- `RequestID`
- `Error:`
- `403`, `AccessDenied`, `ValidationError`, `MalformedPolicy`, etc.

Example snippet:

```shell
RequestID: 1234abcd-5678
Error: AccessDenied: User is not authorized to perform: s3:PutBucketPolicy
```

Now you know:

- the **exact API**
- the **exact permission**
- the **exact request**

## Step 2: Identify the failing AWS API call

Terraform error messages are often truncated. The log is not.

From the log, extract:

- Service (S3, IAM, EC2, etc.)
- API action (`CreateBucket`, `PutBucketPolicy`, `CreateRole`, etc.)
- Region
- Resource ARN (if present)

This is where you stop thinking in Terraform terms and switch to **AWS API mental model**.

## Step 3: Reproduce the failure with AWS CLI (critical skill)

- AWS CLI errors are often **clearer**
- You can iterate faster
- You isolate Terraform from the problem

### Example: Terraform fails creating an S3 bucket policy

Terraform error:

`Error putting S3 policy: AccessDenied`

### Step 3a: Switch to the same identity Terraform uses

Terraform usually uses:

- environment variables
- or an assumed role

Verify:

```bash
aws sts get-caller-identity
```

If this doesn’t match what Terraform should use, stop here — fix credentials first.

### Step 3b: Re-run the equivalent AWS CLI command

Terraform docs + logs tell you which API is called.

Example:

```bash
aws s3api put-bucket-policy \
  --bucket my-bucket \
  --policy file://policy.json
```

Now observe:

- Full AWS error message
- Precise permission missing
- Sometimes *which statement* in the policy is invalid

## Step 4: Use AWS CloudTrail as your ground truth

**CloudTrail is the ultimate “what actually happened” log.**

### How to query

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutBucketPolicy \
  --max-results 5
```

Or filter by:

- `AccessDenied`
- `eventSource`
- `eventName`
- `requestParameters`

CloudTrail tells you:

- exact IAM principal
- exact API
- exact parameters
- explicit deny vs implicit deny

This is where missing permissions or malformed configs become obvious.

## Step 5: Diff Terraform intent vs AWS requirements

Now you ask:

> “What did Terraform *assume* existed, but doesn’t?”

Common incomplete-module issues:

- Missing IAM role or policy
- Missing dependency (`depends_on`)
- Missing required AWS-side object (e.g. KMS key, log group)
- Wrong order of creation
- Resource exists but Terraform doesn’t manage it

### Concrete example: IAM role missing permissions

Terraform resource:

```hcl
resource "aws_iam_role_policy" "example" {
  role   = aws_iam_role.example.id
  policy = data.aws_iam_policy_document.example.json
}
```

Failure:

`AccessDenied: iam:PutRolePolicy`

AWS CLI test:

```bash
aws iam put-role-policy \
  --role-name example \
  --policy-name test \
  --policy-document file://policy.json
```

If this fails → Terraform module is missing **permissions for the *actor***, not the resource.

## Step 6: Use IAM simulation to prove missing permissions

This is *huge* and underused.

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/TerraformRole \
  --action-names s3:PutBucketPolicy
```

Result: `allowed` or `explicitDeny`

Now you have:

- proof
- exact missing permission
- zero guesswork

## Step 7: Examine provider source code (advanced but powerful)

When Terraform behavior is confusing:

- Find the provider resource implementation:
  - GitHub → `terraform-provider-aws`
- Search for the resource
- See:
  - which AWS APIs are called
  - in what order
  - with which parameters

This answers questions like:

- “Why is Terraform calling *this* API?”
- “Why does it need *that* permission?”

## Step 8: Build a minimal repro outside the module

To isolate module incompleteness:

1. Create a tiny `.tf` file
2. Copy only the failing resource
3. Hardcode values
4. Apply in isolation

If it works → the module is missing:

- inputs
- dependencies
- permissions
- assumptions

This is often faster than reading 1,000 lines of module code.

## Step 9: Teach this debugging ladder explicitly

1. Read `terraform apply` error
2. Enable `TF_LOG=TRACE`
3. Identify failing AWS API + Request ID
4. Re-run API using AWS CLI
5. Check CloudTrail
6. Simulate IAM permissions
7. Fix module inputs / IAM / dependencies
8. Re-run plan & apply

> “If you can’t explain which AWS API failed and why, you’re not done debugging.”

## Final mindset shift (this is key)

Terraform failures are rarely “Terraform bugs.”

They are usually:

- undocumented AWS constraints
- missing permissions
- invalid assumptions in modules
- implicit dependencies

Terraform is just the messenger.
