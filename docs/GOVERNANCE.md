
# Query Permissions

```
( read -p "INPUT ADDRESS: " ADDR && [ -z "$ADDR" ] && ADDR=$VALIDATOR_ADDR ) : sekaid query customgov permissions $ADDR
```


# Claim Permissions as Sudo to add new Validators

```
sekaid tx customgov permission whitelist-permission --from validator --keyring-backend=test --permission=$PermCreateSetPermissionsProposal --addr=$(sekaid keys show -a validator --keyring-backend=test) --chain-id=$NETWORK_NAME --fees=100ukex --yes | jq

sekaid tx customgov permission whitelist-permission --from validator --keyring-backend=test --permission=$PermVoteSetPermissionProposal --addr=$(sekaid keys show -a validator --keyring-backend=test) --chain-id=$NETWORK_NAME --fees=100ukex --yes | jq
```


# Create Proposal to Add new Validator
```
read -p "INPUT ADDRESS OF YOUR NEW VALIDATOR: " ADDR && sekaid tx customgov proposal assign-permission $PermClaimValidator --addr=$ADDR --from=validator --keyring-backend=test --chain-id=$NETWORK_NAME --fees=100ukex --yes | jq
```

# Vote Yes on the Latest Proposal

```
LAST_PROPOSAL=$(sekaid query customgov proposals --output json | jq -cr '.proposals | last | .proposal_id') && sekaid tx customgov proposal vote $LAST_PROPOSAL 1 --from=validator --chain-id=$NETWORK_NAME --keyring-backend=test  --fees=100ukex --yes | jq
```

# Wait For Last Proposal Result

```
LAST_PROPOSAL=$(sekaid query customgov proposals --output json | jq -cr '.proposals | last | .proposal_id') && sekaid query customgov votes $LAST_PROPOSAL --output json | jq && sekaid query customgov proposal $LAST_PROPOSAL --output json | jq && echo "Time now: $(date '+%Y-%m-%dT%H:%M:%S')"
```