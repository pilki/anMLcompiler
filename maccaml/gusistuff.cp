/***********************************************************************/
/*                                                                     */
/*                           Objective Caml                            */
/*                                                                     */
/*          Damien Doligez, projet Moscova, INRIA Rocquencourt         */
/*                                                                     */
/*  Copyright 2000 Institut National de Recherche en Informatique et   */
/*  en Automatique.  All rights reserved.  This file is distributed    */
/*  under the terms of the GNU Library General Public License.         */
/*                                                                     */
/***********************************************************************/
/* $Id$ */

#define GUSI_SOURCE
#include <GUSIBasics.h>

extern "C" {
#include "main.h"
}

static void spin_hook_for_gusi (bool wait)
{
  RotateCursor (32);
  if (wait) GetAndProcessEvents (waitEvent, 0, 0);
}

extern "C" void InitialiseGUSI (void)
{
  GUSISetHook (GUSI_SpinHook, (GUSIHook) spin_hook_for_gusi);
}

/**************** B E G I N GUSI CONFIGURATION ****************************
 *
 * GUSI Configuration section generated by GUSI Configurator
 * last modified: Thu Mar 30 18:08:06 2000
 *
 * This section will be overwritten by the next run of Configurator.
 */

#define GUSI_SOURCE
#include <GUSIConfig.h>
#include <sys/cdefs.h>

/* Declarations of Socket Factories */

__BEGIN_DECLS
void GUSIwithInetSockets();
void GUSIwithLocalSockets();
void GUSIwithMTInetSockets();
void GUSIwithMTTcpSockets();
void GUSIwithMTUdpSockets();
void GUSIwithOTInetSockets();
void GUSIwithOTTcpSockets();
void GUSIwithOTUdpSockets();
void GUSIwithPPCSockets();
void GUSISetupFactories();
__END_DECLS

/* Configure Socket Factories */

void GUSISetupFactories()
{
#ifdef GUSISetupFactories_BeginHook
    GUSISetupFactories_BeginHook
#endif
    GUSIwithInetSockets();
    GUSIwithLocalSockets();
    GUSIwithPPCSockets();
#ifdef GUSISetupFactories_EndHook
    GUSISetupFactories_EndHook
#endif
}

/* Declarations of File Devices */

__BEGIN_DECLS
void GUSIwithDConSockets();
void GUSIwithNullSockets();
void GUSISetupDevices();
__END_DECLS

/* Configure File Devices */

void GUSISetupDevices()
{
#ifdef GUSISetupDevices_BeginHook
    GUSISetupDevices_BeginHook
#endif
    GUSIwithNullSockets ();
#ifdef GUSISetupDevices_EndHook
    GUSISetupDevices_EndHook
#endif
}

#ifndef __cplusplus
#error GUSISetupConfig() needs to be written in C++
#endif

GUSIConfiguration::FileSuffix   sSuffices[] = {
    "", '????', '????'
};

extern "C" void GUSISetupConfig()
{
    GUSIConfiguration * config =
        GUSIConfiguration::CreateInstance(GUSIConfiguration::kNoResource);

    config->ConfigureSuffices(
        sizeof(sSuffices)/sizeof(GUSIConfiguration::FileSuffix)-1, sSuffices);
    config->ConfigureAutoInitGraf(false);
    config->ConfigureAutoSpin(false);
    config->ConfigureSigPipe(true);
}

/**************** E N D GUSI CONFIGURATION *************************/
