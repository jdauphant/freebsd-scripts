#!/bin/sh
# Made by Julien DAUPHANT
# base on http://www.keltia.net/howtos/mfsbsd-zfs91/
# Don't forget NEEDED_VARIABLES

ZFS_ROOT_POOL_NAME=${ZFS_ROOT_POOL_NAME:-"tank"}
TANK_MP=${TANK_MP:-"/tmp/${ZFS_ROOT_POOL_NAME}"}

set -x -e
zfs umount -a
zfs set mountpoint=${TANK_MP}/root ${ZFS_ROOT_POOL_NAME}/root
zfs set mountpoint=${TANK_MP}/root/tmp ${ZFS_ROOT_POOL_NAME}/tmp
zfs set mountpoint=${TANK_MP}/root/var ${ZFS_ROOT_POOL_NAME}/var
zfs set mountpoint=${TANK_MP}/root/usr ${ZFS_ROOT_POOL_NAME}/usr
zfs set mountpoint=${TANK_MP}/root/home ${ZFS_ROOT_POOL_NAME}/home
zfs mount -a
