let Replica = https://raw.githubusercontent.com/ReplicaTest/replica-dhall/main/package.dhall
let Test = Replica.Test
let Success = Replica.Status.Success

in { valid = Test :: {command = "echo \"one\""}
       with description = Some "Simple expectations"
   }
