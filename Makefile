# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER
#
# Copyright 2016 Juniper Networks, Inc. 
# All rights reserved.
#
# Licensed under the Juniper Networks Script Software License (the "License").
# You may not use this script file except in compliance with the License, which is located at
# http://www.juniper.net/support/legal/scriptlicense/
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Please make sure to run this file as a root user

master_name = saltmaster
PWD = $(shell pwd)
RUN_PATH := $(PWD)/run
RUN_MINION += $(RUN_PATH)/started_minions.log
RUN_PROXY +=  $(RUN_PATH)/started_proxies.log

DOCKER_EXEC := @docker exec -i -t  
DOCKER_EXEC_MASTER := $(DOCKER_EXEC) $(master_name)

DOCKER_RUN := @docker run -d 
DOCKER_RUN_MASTER := $(DOCKER_RUN) --volume $(PWD)/pillar:/srv/pillar
DOCKER_RUN_MASTER += --volume $(PWD)/reactor:/srv/reactor
DOCKER_RUN_MASTER += --volume $(PWD)/engine:/srv/engine
DOCKER_RUN_MASTER += --volume $(PWD)/docker/salt_master.yaml:/etc/salt/master
DOCKER_RUN_MASTER += --publish 8516:516/udp
DOCKER_LINK := $(DOCKER_RUN) --link $(master_name):$(master_name)
DOCKER_RUN_MINION := $(DOCKER_LINK) --volume $(PWD)/docker/salt_minion.yaml:/etc/salt/minion
DOCKER_RUN_PROXY := $(DOCKER_LINK) --volume $(PWD)/docker/salt_proxy.yaml:/etc/salt/proxy
DOCKER_RUN_PROXY += --volume $(PWD)/pillar:/srv/pillar

STOP_RM_DOCKER = echo "Stopping:$(1)" && docker stop $(1) 1>/dev/null && echo "Removing:" $(1) && docker rm $(1) 1>/dev/null

#TODO: Accept a key automatically when minion/proxy when spinning up.
#ACCEPT_SPECIFIC_KEY = $(DOCKER_EXEC_MASTER) salt-key -ya $(1)

build:
	docker build --rm -t juniper/saltstack .

master-start:
	$(DOCKER_RUN_MASTER) --name $(master_name) juniper/saltstack salt-master
	
	@touch $(RUN_MINION)
	@touch $(RUN_PROXY)

master-shell:
	$(DOCKER_EXEC_MASTER) bash

master-keys:
	$(DOCKER_EXEC_MASTER) salt-key -L

accept-keys:
	$(DOCKER_EXEC_MASTER) salt-key -yA

master-clean:
	@$(call STOP_RM_DOCKER, $(master_name))


minion-start:
ifndef DEVICE
	$(DOCKER_RUN_MINION) juniper/saltstack salt-minion -l warning \
	2>/dev/null 1>>$(RUN_MINION) && echo -n "Started: " && tail -n1 $(RUN_MINION)
else
	$(DOCKER_RUN_MINION) --name $(DEVICE) -h $(DEVICE) juniper/saltstack salt-minion -l warning \
	>/dev/null 2>&1 && if [ $$? -eq 0 ]; then echo "$(DEVICE)" >> $(RUN_MINION); echo "Started: $(DEVICE)"; fi
endif	

minion-shell:
ifndef DEVICE
	$(error DEVICE parameter is not set.)
else
	$(DOCKER_EXEC) $(DEVICE) bash
endif

minion-clean:
ifndef DEVICE
	@while read -r minion; do \
		$(call STOP_RM_DOCKER, $$minion); \
	done <$(RUN_MINION)
	@rm $(RUN_MINION)
	@touch $(RUN_MINION)
else
	@$(call STOP_RM_DOCKER, $(DEVICE))
	@sed -i '/$(DEVICE)/d' $(RUN_MINION)
endif

proxy-start:
ifndef DEVICE
	$(error DEVICE parameter is not set. Please use 'make proxy-start DEVICE=<name>')
else 
	$(DOCKER_RUN_PROXY) --name $(DEVICE) -h $(DEVICE) juniper/saltstack salt-proxy --proxyid=$(DEVICE) -l warning \
	>/dev/null 2>&1 && if [ $$? -eq 0 ]; then echo "$(DEVICE)" >> $(RUN_PROXY); echo "Started: $(DEVICE)"; fi  
endif

proxy-shell: minion-shell

proxy-clean:
ifndef DEVICE
	@while read -r proxy; do \
		$(call STOP_RM_DOCKER, $$proxy); \
	done <$(RUN_PROXY)
	@rm $(RUN_PROXY)
	@touch $(RUN_PROXY)
else
	@$(call STOP_RM_DOCKER, $(DEVICE))
	@sed -i '/$(DEVICE)/d' $(RUN_PROXY)
endif

clean: master-clean minion-clean proxy-clean
