{-# LANGUAGE TemplateHaskell #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

{-| Unittests for ganeti-htools.

-}

{-

Copyright (C) 2009, 2010, 2011, 2012, 2013 Google Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-}

module Test.Ganeti.OpCodes
  ( testOpCodes
  , genOpCodeFromId
  , OpCodes.OpCode(..)
  ) where

import Prelude ()
import Ganeti.Prelude

import Test.HUnit as HUnit
import Test.QuickCheck as QuickCheck

import Control.Monad (when)
import Data.Char
import Data.List
import Data.Maybe
import qualified Data.Map as Map
import qualified Text.JSON as J
import Text.Printf (printf)

import Test.Ganeti.Objects
import Test.Ganeti.Query.Language ()
import Test.Ganeti.TestHelper
import Test.Ganeti.TestCommon
import Test.Ganeti.Types (genReasonTrail)

import Ganeti.BasicTypes
import qualified Ganeti.Constants as C
import qualified Ganeti.ConstantUtils as CU
import qualified Ganeti.OpCodes as OpCodes
import Ganeti.Types
import Ganeti.OpParams
import Ganeti.Objects
import Ganeti.JSON

{-# ANN module "HLint: ignore Use camelCase" #-}

-- * Arbitrary instances

arbitraryOpTagsGet :: Gen OpCodes.OpCode
arbitraryOpTagsGet = do
  kind <- arbitrary
  OpCodes.OpTagsSet kind <$> genTags <*> genOpCodesTagName kind

arbitraryOpTagsSet :: Gen OpCodes.OpCode
arbitraryOpTagsSet = do
  kind <- arbitrary
  OpCodes.OpTagsSet kind <$> genTags <*> genOpCodesTagName kind

arbitraryOpTagsDel :: Gen OpCodes.OpCode
arbitraryOpTagsDel = do
  kind <- arbitrary
  OpCodes.OpTagsDel kind <$> genTags <*> genOpCodesTagName kind

$(genArbitrary ''OpCodes.ReplaceDisksMode)

$(genArbitrary ''DiskAccess)

instance Arbitrary OpCodes.DiskIndex where
  arbitrary = choose (0, C.maxDisks - 1) >>= OpCodes.mkDiskIndex

instance Arbitrary INicParams where
  arbitrary = INicParams <$> genMaybe genNameNE <*> genMaybe genName <*>
              genMaybe genNameNE <*> genMaybe genNameNE <*>
              genMaybe genNameNE <*> genMaybe genName <*>
              genMaybe genNameNE <*> genMaybe genNameNE

instance Arbitrary IDiskParams where
  arbitrary = IDiskParams <$> arbitrary <*> arbitrary <*>
              genMaybe genNameNE <*> genMaybe genNameNE <*>
              genMaybe genNameNE <*> genMaybe genNameNE <*>
              genMaybe genNameNE <*> arbitrary <*>
              genMaybe genNameNE <*> genAndRestArguments

instance Arbitrary RecreateDisksInfo where
  arbitrary = oneof [ pure RecreateDisksAll
                    , RecreateDisksIndices <$> arbitrary
                    , RecreateDisksParams <$> arbitrary
                    ]

instance Arbitrary DdmOldChanges where
  arbitrary = oneof [ DdmOldIndex <$> arbitrary
                    , DdmOldMod   <$> arbitrary
                    ]

instance (Arbitrary a) => Arbitrary (SetParamsMods a) where
  arbitrary = oneof [ pure SetParamsEmpty
                    , SetParamsDeprecated <$> arbitrary
                    , SetParamsNew        <$> arbitrary
                    ]

instance Arbitrary ExportTarget where
  arbitrary = oneof [ ExportTargetLocal <$> genNodeNameNE
                    , ExportTargetRemote <$> pure []
                    ]

arbitraryDataCollector :: Gen (GenericContainer String Bool)
arbitraryDataCollector = do
  els <-  listOf . elements $ CU.toList C.dataCollectorNames
  activation <- vector $ length els
  return . GenericContainer . Map.fromList $ zip els activation

arbitraryDataCollectorInterval :: Gen (Maybe (GenericContainer String Int))
arbitraryDataCollectorInterval = do
  els <-  listOf . elements $ CU.toList C.dataCollectorNames
  intervals <- vector $ length els
  genMaybe . return . containerFromList $ zip els intervals

genOpCodeFromId :: String -> Maybe ConfigData -> Gen OpCodes.OpCode
genOpCodeFromId op_id cfg =
  case op_id of
    "OP_TEST_DELAY" ->
      OpCodes.OpTestDelay <$> arbitrary <*> arbitrary <*>
        genNodeNamesNE <*> return Nothing <*> arbitrary <*> arbitrary <*>
        arbitrary
    "OP_INSTANCE_REPLACE_DISKS" ->
      OpCodes.OpInstanceReplaceDisks <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary <*> genDiskIndices <*>
        genMaybe genNodeNameNE <*> return Nothing <*> genMaybe genNameNE
    "OP_INSTANCE_FAILOVER" ->
      OpCodes.OpInstanceFailover <$> getInstanceName <*> return Nothing <*>
      arbitrary <*> arbitrary <*> genMaybe genNodeNameNE <*>
      return Nothing <*> arbitrary <*> arbitrary <*> genMaybe genNameNE
    "OP_INSTANCE_MIGRATE" ->
      OpCodes.OpInstanceMigrate <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> genMaybe getNodeName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary <*> genMaybe genNameNE <*>
        arbitrary <*> arbitrary
    "OP_TAGS_GET" ->
      arbitraryOpTagsGet
    "OP_TAGS_SEARCH" ->
      OpCodes.OpTagsSearch <$> genNameNE
    "OP_TAGS_SET" ->
      arbitraryOpTagsSet
    "OP_TAGS_DEL" ->
      arbitraryOpTagsDel
    "OP_CLUSTER_POST_INIT" -> pure OpCodes.OpClusterPostInit
    "OP_CLUSTER_RENEW_CRYPTO" -> OpCodes.OpClusterRenewCrypto
       <$> arbitrary -- Node SSL certificates
       <*> arbitrary -- renew_ssh_keys
       <*> arbitrary -- ssh_key_type
       <*> arbitrary -- ssh_key_bits
       <*> arbitrary -- verbose
       <*> arbitrary -- debug
    "OP_CLUSTER_DESTROY" -> pure OpCodes.OpClusterDestroy
    "OP_CLUSTER_QUERY" -> pure OpCodes.OpClusterQuery
    "OP_CLUSTER_VERIFY" ->
      OpCodes.OpClusterVerify <$> arbitrary <*> arbitrary <*>
        genListSet Nothing <*> genListSet Nothing <*> arbitrary <*>
        genMaybe getGroupName <*> arbitrary
    "OP_CLUSTER_VERIFY_CONFIG" ->
      OpCodes.OpClusterVerifyConfig <$> arbitrary <*> arbitrary <*>
        genListSet Nothing <*> arbitrary
    "OP_CLUSTER_VERIFY_GROUP" ->
      OpCodes.OpClusterVerifyGroup <$> getGroupName <*> arbitrary <*>
        arbitrary <*> genListSet Nothing <*> genListSet Nothing <*>
        arbitrary <*> arbitrary
    "OP_CLUSTER_VERIFY_DISKS" ->
      OpCodes.OpClusterVerifyDisks <$> genMaybe getGroupName <*> arbitrary
    "OP_GROUP_VERIFY_DISKS" ->
      OpCodes.OpGroupVerifyDisks <$> getGroupName <*> arbitrary
    "OP_CLUSTER_REPAIR_DISK_SIZES" ->
      OpCodes.OpClusterRepairDiskSizes <$> getInstanceNames
    "OP_CLUSTER_CONFIG_QUERY" ->
      OpCodes.OpClusterConfigQuery <$> genFieldsNE
    "OP_CLUSTER_RENAME" ->
      OpCodes.OpClusterRename <$> genNameNE
    "OP_CLUSTER_SET_PARAMS" ->
      OpCodes.OpClusterSetParams
        <$> arbitrary                    -- force
        <*> emptyMUD                     -- hv_state
        <*> emptyMUD                     -- disk_state
        <*> genMaybe genName             -- vg_name
        <*> genMaybe arbitrary           -- enabled_hypervisors
        <*> genMaybe genEmptyContainer   -- hvparams
        <*> emptyMUD                     -- beparams
        <*> genMaybe genEmptyContainer   -- os_hvp
        <*> genMaybe genEmptyContainer   -- osparams
        <*> genMaybe genEmptyContainer   -- osparams_private_cluster
        <*> genMaybe genEmptyContainer   -- diskparams
        <*> genMaybe arbitrary           -- candidate_pool_size
        <*> genMaybe arbitrary           -- max_running_jobs
        <*> genMaybe arbitrary           -- max_tracked_jobs
        <*> arbitrary                    -- uid_pool
        <*> arbitrary                    -- add_uids
        <*> arbitrary                    -- remove_uids
        <*> arbitrary                    -- maintain_node_health
        <*> arbitrary                    -- prealloc_wipe_disks
        <*> arbitrary                    -- nicparams
        <*> emptyMUD                     -- ndparams
        <*> emptyMUD                     -- ipolicy
        <*> genMaybe genPrintableAsciiString
                                         -- drbd_helper
        <*> genMaybe genPrintableAsciiString
                                         -- default_iallocator
        <*> emptyMUD                     -- default_iallocator_params
        <*> genMaybe genMacPrefix        -- mac_prefix
        <*> genMaybe genPrintableAsciiString
                                         -- master_netdev
        <*> arbitrary                    -- master_netmask
        <*> genMaybe (listOf genPrintableAsciiStringNE)
                                         -- reserved_lvs
        <*> genMaybe (listOf ((,) <$> arbitrary
                                  <*> genPrintableAsciiStringNE))
                                         -- hidden_os
        <*> genMaybe (listOf ((,) <$> arbitrary
                                  <*> genPrintableAsciiStringNE))
                                         -- blacklisted_os
        <*> arbitrary                    -- use_external_mip_script
        <*> arbitrary                    -- enabled_disk_templates
        <*> arbitrary                    -- modify_etc_hosts
        <*> arbitrary                    -- modify_ssh_config
        <*> genMaybe genName             -- file_storage_dir
        <*> genMaybe genName             -- shared_file_storage_dir
        <*> genMaybe genName             -- gluster_file_storage_dir
        <*> genMaybe genPrintableAsciiString
                                         -- install_image
        <*> genMaybe genPrintableAsciiString
                                         -- instance_communication_network
        <*> genMaybe genPrintableAsciiString
                                         -- zeroing_image
        <*> genMaybe (listOf genPrintableAsciiStringNE)
                                         -- compression_tools
        <*> arbitrary                    -- enabled_user_shutdown
        <*> genMaybe arbitraryDataCollector   -- enabled_data_collectors
        <*> arbitraryDataCollectorInterval   -- data_collector_interval
        <*> genMaybe genName             -- diagnose_data_collector_filename
        <*> genMaybe (fromPositive <$> arbitrary) -- maintd round interval
        <*> genMaybe arbitrary           -- enable maintd balancing
        <*> genMaybe arbitrary           -- maintd balancing threshold
        <*> arbitrary                    -- enabled_predictive_queue
    "OP_CLUSTER_REDIST_CONF" -> pure OpCodes.OpClusterRedistConf
    "OP_CLUSTER_ACTIVATE_MASTER_IP" ->
      pure OpCodes.OpClusterActivateMasterIp
    "OP_CLUSTER_DEACTIVATE_MASTER_IP" ->
      pure OpCodes.OpClusterDeactivateMasterIp
    "OP_QUERY" ->
      OpCodes.OpQuery <$> arbitrary <*> arbitrary <*> genNamesNE <*>
      pure Nothing
    "OP_QUERY_FIELDS" ->
      OpCodes.OpQueryFields <$> arbitrary <*> genMaybe genNamesNE
    "OP_OOB_COMMAND" ->
      OpCodes.OpOobCommand <$> getNodeNames <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary <*> (arbitrary `suchThat` (>0))
    "OP_NODE_REMOVE" ->
      OpCodes.OpNodeRemove <$> getNodeName <*> return Nothing <*>
        arbitrary <*> arbitrary
    "OP_NODE_ADD" ->
      OpCodes.OpNodeAdd <$> getNodeName <*> emptyMUD <*> emptyMUD <*>
        genMaybe genNameNE <*> genMaybe genNameNE <*> arbitrary <*>
        genMaybe genNameNE <*> arbitrary <*> arbitrary <*> emptyMUD <*>
        arbitrary <*> arbitrary <*> arbitrary
    "OP_NODE_QUERYVOLS" ->
      OpCodes.OpNodeQueryvols <$> genNamesNE <*> genNodeNamesNE
    "OP_NODE_QUERY_STORAGE" ->
      OpCodes.OpNodeQueryStorage <$> genNamesNE <*> arbitrary <*>
        getNodeNames <*> genMaybe genNameNE
    "OP_NODE_MODIFY_STORAGE" ->
      OpCodes.OpNodeModifyStorage <$> getNodeName <*> return Nothing <*>
        arbitrary <*> genMaybe genNameNE <*> pure emptyJSObject
    "OP_REPAIR_NODE_STORAGE" ->
      OpCodes.OpRepairNodeStorage <$> getNodeName <*> return Nothing <*>
        arbitrary <*> genMaybe genNameNE <*> arbitrary
    "OP_NODE_SET_PARAMS" ->
      OpCodes.OpNodeSetParams <$> getNodeName <*> return Nothing <*>
        arbitrary <*> emptyMUD <*> emptyMUD <*> arbitrary <*> arbitrary <*>
        arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*>
        genMaybe genNameNE <*> emptyMUD <*> arbitrary <*> arbitrary <*>
        arbitrary
    "OP_NODE_POWERCYCLE" ->
      OpCodes.OpNodePowercycle <$> getNodeName <*> return Nothing <*> arbitrary
    "OP_NODE_MIGRATE" ->
      OpCodes.OpNodeMigrate <$> getNodeName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> genMaybe getNodeName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> genMaybe genNameNE
    "OP_NODE_EVACUATE" ->
      OpCodes.OpNodeEvacuate <$> arbitrary <*> getNodeName <*>
        return Nothing <*> genMaybe getNodeName <*> return Nothing <*>
        genMaybe genNameNE <*> arbitrary <*> arbitrary
    "OP_INSTANCE_CREATE" ->
      OpCodes.OpInstanceCreate
        <$> genFQDN                         -- instance_name
        <*> arbitrary                       -- force_variant
        <*> arbitrary                       -- wait_for_sync
        <*> arbitrary                       -- name_check
        <*> arbitrary                       -- ignore_ipolicy
        <*> arbitrary                       -- opportunistic_locking
        <*> pure emptyJSObject              -- beparams
        <*> arbitrary                       -- disks
        <*> arbitrary                       -- disk_template
        <*> genMaybe getGroupName           -- group_name
        <*> arbitrary                       -- file_driver
        <*> genMaybe genNameNE              -- file_storage_dir
        <*> pure emptyJSObject              -- hvparams
        <*> arbitrary                       -- hypervisor
        <*> genMaybe genNameNE              -- iallocator
        <*> arbitrary                       -- identify_defaults
        <*> arbitrary                       -- ip_check
        <*> arbitrary                       -- conflicts_check
        <*> arbitrary                       -- mode
        <*> arbitrary                       -- nics
        <*> arbitrary                       -- no_install
        <*> pure emptyJSObject              -- osparams
        <*> genMaybe arbitraryPrivateJSObj  -- osparams_private
        <*> genMaybe arbitrarySecretJSObj   -- osparams_secret
        <*> genMaybe genNameNE              -- os_type
        <*> genMaybe getNodeName            -- pnode
        <*> return Nothing                  -- pnode_uuid
        <*> genMaybe getNodeName            -- snode
        <*> return Nothing                  -- snode_uuid
        <*> genMaybe (pure [])              -- source_handshake
        <*> genMaybe genNodeNameNE          -- source_instance_name
        <*> arbitrary                       -- source_shutdown_timeout
        <*> genMaybe genNodeNameNE          -- source_x509_ca
        <*> return Nothing                  -- src_node
        <*> genMaybe genNodeNameNE          -- src_node_uuid
        <*> genMaybe genNameNE              -- src_path
        <*> genPrintableAsciiString         -- compress
        <*> arbitrary                       -- start
        <*> arbitrary                       -- forthcoming
        <*> arbitrary                       -- commit
        <*> (genTags >>= mapM mkNonEmpty)   -- tags
        <*> arbitrary                       -- instance_communication
        <*> arbitrary                       -- helper_startup_timeout
        <*> arbitrary                       -- helper_shutdown_timeout
    "OP_INSTANCE_MULTI_ALLOC" ->
      OpCodes.OpInstanceMultiAlloc <$> arbitrary <*> genMaybe genNameNE <*>
      pure []
    "OP_INSTANCE_REINSTALL" ->
      OpCodes.OpInstanceReinstall <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> genMaybe genNameNE <*> genMaybe (pure emptyJSObject)
        <*> genMaybe arbitraryPrivateJSObj <*> genMaybe arbitrarySecretJSObj
        <*> arbitrary <*> arbitrary
        <*> genMaybe (listOf genPrintableAsciiString)
        <*> genMaybe (listOf genPrintableAsciiString)
    "OP_INSTANCE_REMOVE" ->
      OpCodes.OpInstanceRemove <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary
    "OP_INSTANCE_RENAME" ->
      OpCodes.OpInstanceRename <$> getInstanceName <*> return Nothing <*>
        (genFQDN >>= mkNonEmpty) <*> arbitrary <*> arbitrary
    "OP_INSTANCE_STARTUP" ->
      OpCodes.OpInstanceStartup <$>
        getInstanceName <*>     -- instance_name
        return Nothing <*>      -- instance_uuid
        arbitrary <*>           -- force
        arbitrary <*>           -- ignore_offline_nodes
        pure emptyJSObject <*>  -- hvparams
        pure emptyJSObject <*>  -- beparams
        arbitrary <*>           -- no_remember
        arbitrary <*>           -- startup_paused
        arbitrary               -- shutdown_timeout
    "OP_INSTANCE_SHUTDOWN" ->
      OpCodes.OpInstanceShutdown <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary
    "OP_INSTANCE_REBOOT" ->
      OpCodes.OpInstanceReboot <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary
    "OP_INSTANCE_MOVE" ->
      OpCodes.OpInstanceMove <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> getNodeName <*>
        return Nothing <*> genPrintableAsciiString <*> arbitrary
    "OP_INSTANCE_CONSOLE" -> OpCodes.OpInstanceConsole <$> getInstanceName <*>
        return Nothing
    "OP_INSTANCE_ACTIVATE_DISKS" ->
      OpCodes.OpInstanceActivateDisks <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary
    "OP_INSTANCE_DEACTIVATE_DISKS" ->
      OpCodes.OpInstanceDeactivateDisks <$> genFQDN <*> return Nothing <*>
        arbitrary
    "OP_INSTANCE_RECREATE_DISKS" ->
      OpCodes.OpInstanceRecreateDisks <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> genNodeNamesNE <*> return Nothing <*> genMaybe getNodeName
    "OP_INSTANCE_QUERY_DATA" ->
      OpCodes.OpInstanceQueryData <$> arbitrary <*>
        getInstanceNames <*> arbitrary
    "OP_INSTANCE_SET_PARAMS" ->
      OpCodes.OpInstanceSetParams
        <$> getInstanceName                 -- instance_name
        <*> return Nothing                  -- instance_uuid
        <*> arbitrary                       -- force
        <*> arbitrary                       -- force_variant
        <*> arbitrary                       -- ignore_ipolicy
        <*> arbitrary                       -- nics
        <*> arbitrary                       -- disks
        <*> pure emptyJSObject              -- beparams
        <*> arbitrary                       -- runtime_mem
        <*> pure emptyJSObject              -- hvparams
        <*> arbitrary                       -- disk_template
        <*> pure emptyJSObject              -- ext_params
        <*> arbitrary                       -- file_driver
        <*> genMaybe genNameNE              -- file_storage_dir
        <*> genMaybe getNodeName            -- pnode
        <*> return Nothing                  -- pnode_uuid
        <*> genMaybe getNodeName            -- remote_node
        <*> return Nothing                  -- remote_node_uuid
        <*> genMaybe genNameNE              -- iallocator
        <*> genMaybe genNameNE              -- os_name
        <*> pure emptyJSObject              -- osparams
        <*> genMaybe arbitraryPrivateJSObj  -- osparams_private
        <*> arbitrary                       -- clear_osparams
        <*> arbitrary                       -- clear_osparams_private
        <*> genMaybe (listOf genPrintableAsciiString) -- remove_osparams
        <*> genMaybe (listOf genPrintableAsciiString) -- remove_osparams_private
        <*> arbitrary                       -- wait_for_sync
        <*> arbitrary                       -- offline
        <*> arbitrary                       -- conflicts_check
        <*> arbitrary                       -- hotplug
        <*> arbitrary                       -- hotplug_if_possible
        <*> arbitrary                       -- instance_communication
    "OP_INSTANCE_GROW_DISK" ->
      OpCodes.OpInstanceGrowDisk <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary
    "OP_INSTANCE_CHANGE_GROUP" ->
      OpCodes.OpInstanceChangeGroup <$> getInstanceName <*> return Nothing <*>
        arbitrary <*> genMaybe genNameNE <*>
        genMaybe (resize maxNodes (listOf genNameNE))
    "OP_GROUP_ADD" ->
      OpCodes.OpGroupAdd <$> genNameNE <*> arbitrary <*>
        emptyMUD <*> genMaybe genEmptyContainer <*>
        emptyMUD <*> emptyMUD <*> emptyMUD
    "OP_GROUP_ASSIGN_NODES" ->
      OpCodes.OpGroupAssignNodes <$> getGroupName <*>
        arbitrary <*> getNodeNames <*> return Nothing
    "OP_GROUP_SET_PARAMS" ->
      OpCodes.OpGroupSetParams <$> getGroupName <*>
        arbitrary <*> emptyMUD <*> genMaybe genEmptyContainer <*>
        emptyMUD <*> emptyMUD <*> emptyMUD
    "OP_GROUP_REMOVE" ->
      OpCodes.OpGroupRemove <$> getGroupName
    "OP_GROUP_RENAME" ->
      OpCodes.OpGroupRename <$> getGroupName <*> genNameNE
    "OP_GROUP_EVACUATE" ->
      OpCodes.OpGroupEvacuate <$> getGroupName <*>
        arbitrary <*> genMaybe genNameNE <*> genMaybe genNamesNE <*>
        arbitrary <*> arbitrary
    "OP_OS_DIAGNOSE" ->
      OpCodes.OpOsDiagnose <$> genFieldsNE <*> genNamesNE
    "OP_EXT_STORAGE_DIAGNOSE" ->
      OpCodes.OpOsDiagnose <$> genFieldsNE <*> genNamesNE
    "OP_BACKUP_PREPARE" ->
      OpCodes.OpBackupPrepare <$> getInstanceName <*>
        return Nothing <*> arbitrary
    "OP_BACKUP_EXPORT" ->
      OpCodes.OpBackupExport
        <$> getInstanceName          -- instance_name
        <*> return Nothing           -- instance_uuid
        <*> genPrintableAsciiString  -- compress
        <*> arbitrary                -- shutdown_timeout
        <*> arbitrary                -- target_node
        <*> return Nothing           -- target_node_uuid
        <*> arbitrary                -- shutdown
        <*> arbitrary                -- remove_instance
        <*> arbitrary                -- ignore_remove_failures
        <*> arbitrary                -- mode
        <*> genMaybe (pure [])       -- x509_key_name
        <*> genMaybe genNameNE       -- destination_x509_ca
        <*> arbitrary                -- zero_free_space
        <*> arbitrary                -- zeroing_timeout_fixed
        <*> arbitrary                -- zeroing_timeout_per_mib
        <*> arbitrary                -- long_sleep
    "OP_BACKUP_REMOVE" ->
      OpCodes.OpBackupRemove <$> getInstanceName <*> return Nothing
    "OP_TEST_ALLOCATOR" ->
      OpCodes.OpTestAllocator <$> arbitrary <*> arbitrary <*>
        genNameNE <*> genMaybe (pure []) <*> genMaybe (pure []) <*>
        arbitrary <*> genMaybe genNameNE <*>
        (genTags >>= mapM mkNonEmpty) <*>
        arbitrary <*> arbitrary <*> genMaybe genNameNE <*>
        arbitrary <*> genMaybe genNodeNamesNE <*> arbitrary <*>
        genMaybe genNamesNE <*> arbitrary <*> arbitrary <*>
        genMaybe getGroupName
    "OP_TEST_JQUEUE" ->
      OpCodes.OpTestJqueue <$> arbitrary <*> arbitrary <*>
        resize 20 (listOf genFQDN) <*> arbitrary
    "OP_TEST_OS_PARAMS" ->
      OpCodes.OpTestOsParams <$> genMaybe arbitrarySecretJSObj
    "OP_TEST_DUMMY" ->
      OpCodes.OpTestDummy <$> pure J.JSNull <*> pure J.JSNull <*>
        pure J.JSNull <*> pure J.JSNull
    "OP_NETWORK_ADD" ->
      OpCodes.OpNetworkAdd <$> genNameNE <*> genIPv4Network <*>
        genMaybe genIPv4Address <*> pure Nothing <*> pure Nothing <*>
        genMaybe genMacPrefix <*> genMaybe (listOf genIPv4Address) <*>
        arbitrary <*> (genTags >>= mapM mkNonEmpty)
    "OP_NETWORK_REMOVE" ->
      OpCodes.OpNetworkRemove <$> genNameNE <*> arbitrary
    "OP_NETWORK_SET_PARAMS" ->
      OpCodes.OpNetworkSetParams <$> genNameNE <*>
        genMaybe genIPv4Address <*> pure Nothing <*> pure Nothing <*>
        genMaybe genMacPrefix <*> genMaybe (listOf genIPv4Address) <*>
        genMaybe (listOf genIPv4Address)
    "OP_NETWORK_CONNECT" ->
      OpCodes.OpNetworkConnect <$> getGroupName <*>
        genNameNE <*> arbitrary <*> genNameNE <*> genPrintableAsciiString <*>
        arbitrary
    "OP_NETWORK_DISCONNECT" ->
      OpCodes.OpNetworkDisconnect <$> getGroupName <*>
        genNameNE
    "OP_RESTRICTED_COMMAND" ->
      OpCodes.OpRestrictedCommand <$> arbitrary <*> getNodeNames <*>
        return Nothing <*> genNameNE
    "OP_REPAIR_COMMAND" ->
      OpCodes.OpRepairCommand <$> getNodeName <*> genNameNE <*>
        genMaybe genPrintableAsciiStringNE
    _ -> fail $ "Undefined arbitrary for opcode " ++ op_id
  where getInstanceName =
          case cfg of
               Just c -> fmap (fromMaybe "") . genValidInstanceName $ c
               Nothing -> genFQDN
        getNodeName = maybe genFQDN genValidNodeName cfg >>= mkNonEmpty
        getGroupName = maybe genName genValidGroupName cfg >>= mkNonEmpty
        getInstanceNames = resize maxNodes (listOf getInstanceName) >>=
                           mapM mkNonEmpty
        getNodeNames = resize maxNodes (listOf getNodeName)

instance Arbitrary OpCodes.OpCode where
  arbitrary = do
    op_id <- elements OpCodes.allOpIDs
    genOpCodeFromId op_id Nothing

instance Arbitrary OpCodes.CommonOpParams where
  arbitrary = OpCodes.CommonOpParams <$> arbitrary <*> arbitrary <*>
                arbitrary <*> resize 5 arbitrary <*> genMaybe genName <*>
                genReasonTrail

-- * Helper functions

-- | Empty JSObject.
emptyJSObject :: J.JSObject J.JSValue
emptyJSObject = J.toJSObject []

-- | Empty maybe unchecked dictionary.
emptyMUD :: Gen (Maybe (J.JSObject J.JSValue))
emptyMUD = genMaybe $ pure emptyJSObject

-- | Generates an empty container.
genEmptyContainer :: (Ord a) => Gen (GenericContainer a b)
genEmptyContainer = pure . GenericContainer $ Map.fromList []

-- | Generates list of disk indices.
genDiskIndices :: Gen [DiskIndex]
genDiskIndices = do
  cnt <- choose (0, C.maxDisks)
  genUniquesList cnt arbitrary

-- | Generates a list of node names.
genNodeNames :: Gen [String]
genNodeNames = resize maxNodes (listOf genFQDN)

-- | Generates a list of node names in non-empty string type.
genNodeNamesNE :: Gen [NonEmptyString]
genNodeNamesNE = genNodeNames >>= mapM mkNonEmpty

-- | Gets a node name in non-empty type.
genNodeNameNE :: Gen NonEmptyString
genNodeNameNE = genFQDN >>= mkNonEmpty

-- | Gets a name (non-fqdn) in non-empty type.
genNameNE :: Gen NonEmptyString
genNameNE = genName >>= mkNonEmpty

-- | Gets a list of names (non-fqdn) in non-empty type.
genNamesNE :: Gen [NonEmptyString]
genNamesNE = resize maxNodes (listOf genNameNE)

-- | Returns a list of non-empty fields.
genFieldsNE :: Gen [NonEmptyString]
genFieldsNE = genFields >>= mapM mkNonEmpty

-- | Generate a 3-byte MAC prefix.
genMacPrefix :: Gen NonEmptyString
genMacPrefix = do
  octets <- vectorOf 3 $ choose (0::Int, 255)
  mkNonEmpty . intercalate ":" $ map (printf "%02x") octets

-- | JSObject of arbitrary data.
--
-- Since JSValue does not implement Arbitrary, I'll simply generate
-- (String, String) objects.
arbitraryPrivateJSObj :: Gen (J.JSObject (Private J.JSValue))
arbitraryPrivateJSObj =
  constructor <$> (fromNonEmpty <$> genNameNE)
              <*> (fromNonEmpty <$> genNameNE)
    where constructor k v = showPrivateJSObject [(k, v)]

-- | JSObject of arbitrary secret data.
arbitrarySecretJSObj :: Gen (J.JSObject (Secret J.JSValue))
arbitrarySecretJSObj =
  constructor <$> (fromNonEmpty <$> genNameNE)
              <*> (fromNonEmpty <$> genNameNE)
    where constructor k v = showSecretJSObject [(k, v)]

-- | Arbitrary instance for MetaOpCode, defined here due to TH ordering.
$(genArbitrary ''OpCodes.MetaOpCode)

-- | Small helper to check for a failed JSON deserialisation
isJsonError :: J.Result a -> Bool
isJsonError (J.Error _) = True
isJsonError _           = False

-- * Test cases

-- | Check that opcode serialization is idempotent.
prop_serialization :: OpCodes.OpCode -> Property
prop_serialization = testSerialisation

-- | Check that Python and Haskell defined the same opcode list.
case_AllDefined :: HUnit.Assertion
case_AllDefined = do
  py_stdout <-
     runPython "from ganeti import opcodes\n\
               \from ganeti import serializer\n\
               \import sys\n\
               \print serializer.Dump([opid for opid in opcodes.OP_MAPPING])\n"
               ""
     >>= checkPythonResult
  py_ops <- case J.decode py_stdout::J.Result [String] of
               J.Ok ops -> return ops
               J.Error msg ->
                 HUnit.assertFailure ("Unable to decode opcode names: " ++ msg)
                 -- this already raised an expection, but we need it
                 -- for proper types
                 >> fail "Unable to decode opcode names"
  let hs_ops = sort OpCodes.allOpIDs
      extra_py = py_ops \\ hs_ops
      extra_hs = hs_ops \\ py_ops
  HUnit.assertBool ("Missing OpCodes from the Haskell code:\n" ++
                    unlines extra_py) (null extra_py)
  HUnit.assertBool ("Extra OpCodes in the Haskell code:\n" ++
                    unlines extra_hs) (null extra_hs)

-- | Custom HUnit test case that forks a Python process and checks
-- correspondence between Haskell-generated OpCodes and their Python
-- decoded, validated and re-encoded version.
--
-- Note that we have a strange beast here: since launching Python is
-- expensive, we don't do this via a usual QuickProperty, since that's
-- slow (I've tested it, and it's indeed quite slow). Rather, we use a
-- single HUnit assertion, and in it we manually use QuickCheck to
-- generate 500 opcodes times the number of defined opcodes, which
-- then we pass in bulk to Python. The drawbacks to this method are
-- two fold: we cannot control the number of generated opcodes, since
-- HUnit assertions don't get access to the test options, and for the
-- same reason we can't run a repeatable seed. We should probably find
-- a better way to do this, for example by having a
-- separately-launched Python process (if not running the tests would
-- be skipped).
case_py_compat_types :: HUnit.Assertion
case_py_compat_types = do
  let num_opcodes = length OpCodes.allOpIDs * 100
  opcodes <- genSample (vectorOf num_opcodes
                                   (arbitrary::Gen OpCodes.MetaOpCode))
  let with_sum = map (\o -> (OpCodes.opSummary $
                             OpCodes.metaOpCode o, o)) opcodes
      serialized = J.encode opcodes
  -- check for non-ASCII fields, usually due to 'arbitrary :: String'
  mapM_ (\op -> when (any (not . isAscii) (J.encode op)) .
                HUnit.assertFailure $
                  "OpCode has non-ASCII fields: " ++ show op
        ) opcodes
  py_stdout <-
     runPython "from ganeti import opcodes\n\
               \from ganeti import serializer\n\
               \import sys\n\
               \op_data = serializer.Load(sys.stdin.read())\n\
               \decoded = [opcodes.OpCode.LoadOpCode(o) for o in op_data]\n\
               \for op in decoded:\n\
               \  op.Validate(True)\n\
               \encoded = [(op.Summary(), op.__getstate__())\n\
               \           for op in decoded]\n\
               \print serializer.Dump(\
               \  encoded,\
               \  private_encoder=serializer.EncodeWithPrivateFields)"
               serialized
     >>= checkPythonResult
  let deserialised =
        J.decode py_stdout::J.Result [(String, OpCodes.MetaOpCode)]
  decoded <- case deserialised of
               J.Ok ops -> return ops
               J.Error msg ->
                 HUnit.assertFailure ("Unable to decode opcodes: " ++ msg)
                 -- this already raised an expection, but we need it
                 -- for proper types
                 >> fail "Unable to decode opcodes"
  HUnit.assertEqual "Mismatch in number of returned opcodes"
    (length decoded) (length with_sum)
  mapM_ (uncurry (HUnit.assertEqual "Different result after encoding/decoding")
        ) $ zip with_sum decoded

-- | Custom HUnit test case that forks a Python process and checks
-- correspondence between Haskell OpCodes fields and their Python
-- equivalent.
case_py_compat_fields :: HUnit.Assertion
case_py_compat_fields = do
  let hs_fields = sort $ map (\op_id -> (op_id, OpCodes.allOpFields op_id))
                         OpCodes.allOpIDs
  py_stdout <-
     runPython "from ganeti import opcodes\n\
               \import sys\n\
               \from ganeti import serializer\n\
               \fields = [(k, sorted([p[0] for p in v.OP_PARAMS]))\n\
               \           for k, v in opcodes.OP_MAPPING.items()]\n\
               \print serializer.Dump(fields)" ""
     >>= checkPythonResult
  let deserialised = J.decode py_stdout::J.Result [(String, [String])]
  py_fields <- case deserialised of
                 J.Ok v -> return $ sort v
                 J.Error msg ->
                   HUnit.assertFailure ("Unable to decode op fields: " ++ msg)
                   -- this already raised an expection, but we need it
                   -- for proper types
                   >> fail "Unable to decode op fields"
  HUnit.assertEqual "Mismatch in number of returned opcodes"
    (length hs_fields) (length py_fields)
  HUnit.assertEqual "Mismatch in defined OP_IDs"
    (map fst hs_fields) (map fst py_fields)
  mapM_ (\((py_id, py_flds), (hs_id, hs_flds)) -> do
           HUnit.assertEqual "Mismatch in OP_ID" py_id hs_id
           HUnit.assertEqual ("Mismatch in fields for " ++ hs_id)
             py_flds hs_flds
        ) $ zip hs_fields py_fields

-- | Checks that setOpComment works correctly.
prop_setOpComment :: OpCodes.MetaOpCode -> String -> Property
prop_setOpComment op comment =
  let (OpCodes.MetaOpCode common _) = OpCodes.setOpComment comment op
  in OpCodes.opComment common ==? Just comment

-- | Tests wrong (negative) disk index.
prop_mkDiskIndex_fail :: QuickCheck.Positive Int -> Property
prop_mkDiskIndex_fail (Positive i) =
  case mkDiskIndex (negate i) of
    Bad msg -> counterexample "error message " $
               "Invalid value" `isPrefixOf` msg
    Ok v -> failTest $ "Succeeded to build disk index '" ++ show v ++
                       "' from negative value " ++ show (negate i)

-- | Tests a few invalid 'readRecreateDisks' cases.
case_readRecreateDisks_fail :: Assertion
case_readRecreateDisks_fail = do
  assertBool "null" $
    isJsonError (J.readJSON J.JSNull::J.Result RecreateDisksInfo)
  assertBool "string" $
    isJsonError (J.readJSON (J.showJSON "abc")::J.Result RecreateDisksInfo)

-- | Tests a few invalid 'readDdmOldChanges' cases.
case_readDdmOldChanges_fail :: Assertion
case_readDdmOldChanges_fail = do
  assertBool "null" $
    isJsonError (J.readJSON J.JSNull::J.Result DdmOldChanges)
  assertBool "string" $
    isJsonError (J.readJSON (J.showJSON "abc")::J.Result DdmOldChanges)

-- | Tests a few invalid 'readExportTarget' cases.
case_readExportTarget_fail :: Assertion
case_readExportTarget_fail = do
  assertBool "null" $
    isJsonError (J.readJSON J.JSNull::J.Result ExportTarget)
  assertBool "int" $
    isJsonError (J.readJSON (J.showJSON (5::Int))::J.Result ExportTarget)

testSuite "OpCodes"
            [ 'prop_serialization
            , 'case_AllDefined
            , 'case_py_compat_types
            , 'case_py_compat_fields
            , 'prop_setOpComment
            , 'prop_mkDiskIndex_fail
            , 'case_readRecreateDisks_fail
            , 'case_readDdmOldChanges_fail
            , 'case_readExportTarget_fail
            ]
