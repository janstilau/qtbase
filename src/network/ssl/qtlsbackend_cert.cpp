/****************************************************************************
**
** Copyright (C) 2021 The Qt Company Ltd.
** Contact: https://www.qt.io/licensing/
**
** This file is part of the QtNetwork module of the Qt Toolkit.
**
** $QT_BEGIN_LICENSE:LGPL$
** Commercial License Usage
** Licensees holding valid commercial Qt licenses may use this file in
** accordance with the commercial license agreement provided with the
** Software or, alternatively, in accordance with the terms contained in
** a written agreement between you and The Qt Company. For licensing terms
** and conditions see https://www.qt.io/terms-conditions. For further
** information use the contact form at https://www.qt.io/contact-us.
**
** GNU Lesser General Public License Usage
** Alternatively, this file may be used under the terms of the GNU Lesser
** General Public License version 3 as published by the Free Software
** Foundation and appearing in the file LICENSE.LGPL3 included in the
** packaging of this file. Please review the following information to
** ensure the GNU Lesser General Public License version 3 requirements
** will be met: https://www.gnu.org/licenses/lgpl-3.0.html.
**
** GNU General Public License Usage
** Alternatively, this file may be used under the terms of the GNU
** General Public License version 2.0 or (at your option) the GNU General
** Public license version 3 or any later version approved by the KDE Free
** Qt Foundation. The licenses are as published by the Free Software
** Foundation and appearing in the file LICENSE.GPL2 and LICENSE.GPL3
** included in the packaging of this file. Please review the following
** information to ensure the GNU General Public License requirements will
** be met: https://www.gnu.org/licenses/gpl-2.0.html and
** https://www.gnu.org/licenses/gpl-3.0.html.
**
** $QT_END_LICENSE$
**
****************************************************************************/

#include "qtlsbackend_cert_p.h"

#ifdef QT_NO_SSL

#include "qx509_generic_p.h"

#include <qssl.h>

#include <qlist.h>

QT_BEGIN_NAMESPACE

Q_LOGGING_CATEGORY(lcTlsBackend, "qt.tlsbackend.cert-only");

QString QTlsBackendCertOnly::backendName() const
{
    return QStringLiteral("cert-only");
}


QList<QSsl::SslProtocol> QTlsBackendCertOnly::supportedProtocols() const
{
    return {};
}

QList<QSsl::SupportedFeature> QTlsBackendCertOnly::supportedFeatures() const
{
    return {};
}

QList<QSsl::ImplementedClass> QTlsBackendCertOnly::implementedClasses() const
{
    QList<QSsl::ImplementedClass> classes;
    classes << QSsl::ImplementedClass::Certificate;

    return classes;
}

QTlsPrivate::X509Certificate *QTlsBackendCertOnly::createCertificate() const
{
    return new QTlsPrivate::X509CertificateGeneric;
}

QTlsPrivate::X509PemReaderPtr QTlsBackendCertOnly::X509PemReader() const
{
    return QTlsPrivate::X509CertificateGeneric::certificatesFromPem;
}

QTlsPrivate::X509DerReaderPtr QTlsBackendCertOnly::X509DerReader() const
{
    return QTlsPrivate::X509CertificateGeneric::certificatesFromDer;
}

QT_END_NAMESPACE

#endif // QT_NO_SSL

