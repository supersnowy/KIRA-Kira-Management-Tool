## Kira Management Tool

### Minimum Requirements

```
RAM: 3072MB
```

### 1. Install & Update Ubuntu 20.04

```
apt update
```

### 2. Open terminal or SSH console & logs in as sudo

```
sudo -s
```

### 3. Executes following command that will setup the environment by downloading setup file from github or other source, check integrity of the file, start it and install all essential dependencies

```
cd /tmp && wget https://raw.githubusercontent.com/KiraCore/kira/master/workstation/init.sh -O ./i.sh && \
 chmod 555 -v ./i.sh && H=$(sha256sum ./i.sh | awk '{ print $1 }') && read -p "Is '$H' a [V]alid SHA256 ?: "$'\n' -n 1 V && \
 [ "${V,,}" == "v" ] && ./i.sh master || echo "Hash was NOT accepted by the user"
```

Demo Mode Example:

```
cd /tmp && read -p "Input branch name: " BRANCH && \
 wget https://raw.githubusercontent.com/KiraCore/kira/$BRANCH/workstation/init.sh -O ./i.sh && \
 chmod 555 -v ./i.sh && H=$(sha256sum ./i.sh | awk '{ print $1 }') && read -p "Is '$H' a [V]alid SHA256 ?: "$'\n' -n 1 V && \
 [ "${V,,}" == "v" ] && ./i.sh "$BRANCH" || echo "Hash was NOT accepted by the user"
```

### 4. Setup script will further download and install kira management tool

### 5. By typing kira in the terminal user will have ability to deploy, scale and manage his infrastructure

---

### 1. Demo Mode

```
KIRA_REGISTRY_SUBNET="10.1.0.0/16"
KIRA_VALIDATOR_SUBNET="10.2.0.0/16"
KIRA_SENTRY_SUBNET="10.3.0.0/16"
KIRA_SERVICE_SUBNET="10.4.0.0/16"
```

```
KIRA_REGISTRY_DNS="registry.regnet.local"
KIRA_VALIDATOR_DNS="validator.kiranet.local"
KIRA_SENTRY_DNS="sentry.sentrynet.local"
KIRA_PRIV_SENTRY_DNS="priv-sentry.sentrynet.local"
KIRA_INTERX_DNS="interx.servicenet.local"
KIRA_FRONTEND_DNS="fontend.servicenet.local"
```

### 2. Full Node Mode

### 3. Validator Mode

## How to interact with sekaid using console

### - How to update validator information

Updating validator information is not currently available. This will be added later.

### - How to create a proposal to add new validator

First, the following command adds a new validator's key `val2`.

```
sekaid keys add val2 --keyring-backend=test --home=$SEKAID_HOME
```

Next, the following command whitelists `PermCreateSetPermissionsProposal` (defined as `4`) permission of the `validator`. This permission should be whitelisted to create a proposal. (please replace the chain-id with your chain id)

```
sekaid tx customgov permission whitelist-permission --from validator --keyring-backend=test --permission=4 --addr=$(sekaid keys show -a validator --keyring-backend=test --home=$SEKAID_HOME) --chain-id=testing --fees=100ukex --home=$SEKAID_HOME --yes
```

The following command creates a proposal that adds a new validator `val2`.

```
sekaid tx customgov proposal assign-permission 2 --addr=$(sekaid keys show -a val2 --keyring-backend=test --home=$SEKAID_HOME) --from=validator --keyring-backend=test --home=$SEKAID_HOME --chain-id=testing --fees=100ukex --yes
```

Then, we can check if the proposal is created or not with the following command.

```
sekaid query customgov proposals
```

### - How to vote on a proposal to add a new validator

First, the `PermVoteSetPermissionProposal` (defined as `5`) permission should be whitelisted on `validator` to participate on the vote. The following command whitelists `PermVoteSetPermissionProposal` permission of the `validator`.

```
sekaid tx customgov permission whitelist-permission --from validator --keyring-backend=test --permission=5 --addr=$(sekaid keys show -a validator --keyring-backend=test --home=$SEKAID_HOME) --chain-id=testing --fees=100ukex --home=$SEKAID_HOME --yes
```

Then, we can vote on a proposal with the following command. Here, we assume the proposal's id is `1`.

```
sekaid tx customgov proposal vote 1 1 --from validator --keyring-backend=test --home=$SEKAID_HOME --chain-id=testing --fees=100ukex --yes
```

### - How to create a validator after proposal passed

First, let's get the val-address of the `val2`.

```
validatorKey=$(sekaid val-address $(sekaid keys show -a val2 --keyring-backend=test))
```

Then, let's claim the validator seat which performs to create a validator.

```
sekaid tx claim-validator-seat --from validator --keyring-backend=test --home=$SEKAID_HOME --validator-key=$validatorKey --moniker="validator" --chain-id=testing --fees=100ukex --yes
```

### - How to make token transactions in different currencies

Let's add a new token (stake token) as fee currency. After that, we can make token transactions with newly registered token.

First, we should whitelist `PermUpsertTokenRate` (defined as `8`) permission to a validator to create a proposal that registers new token.

```
sekaid tx customgov permission whitelist-permission --from validator --keyring-backend=test --permission=8 --addr=$(sekaid keys show -a validator --keyring-backend=test --home=$SEKAID_HOME) --chain-id=testing --fees=100ukex --home=$SEKAID_HOME --yes
```

Then, the following command registers the `stake` token as fee currency. (1ukex=100stake)

```
sekaid tx tokens upsert-rate --from validator --keyring-backend=test --denom="stake" --rate="0.01" --fee_payments=true --chain-id=testing --fees=100ukex --home=$SEKAID_HOME --yes
```

You can query the `stake` token's rate with the following command.

```
sekaid query tokens rate stake
```

Try to spend `stake` token as fee with the following commands. You can see the `--fees` flag is set as `10000stake`

```
sekaid tx tokens upsert-rate --from validator --keyring-backend=test --denom="valstake" --rate="0.01" --fee_payments=true --chain-id=testing --fees=10000stake --home=$SEKAID_HOME --yes
```

### - How to create a proposal to create an upsert token alias

```
sekaid tx customgov proposal assign-permission 2 --addr=$(sekaid keys show -a val2 --keyring-backend=test --home=$SEKAID_HOME) --from=validator --keyring-backend=test --home=$SEKAID_HOME --chain-id=testing --fees=100ukex --yes
```

### - How to modify how long the proposal take

```
sekaid tx customgov set-network-properties --from validator --min_tx_fee="2" --max_tx_fee="20000" --keyring-backend=test --chain-id=testing --fees=100ukex --home=$SEKAID_HOME
```
