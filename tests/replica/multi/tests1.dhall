let Replica = https://raw.githubusercontent.com/ReplicaTest/replica-dhall/main/package.dhall
let Test = Replica.Test

in { one = Test :: {command = "echo \"one\""}
   }

